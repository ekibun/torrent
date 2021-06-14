import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/peer.dart';

class KNode {
  final ByteString id;
  final InternetAddress ip;
  final int port;
  final int timestamp;
  KNode(this.id, this.ip, this.port)
      : timestamp = DateTime.now().millisecondsSinceEpoch;

  static KNode clone(KNode node) => KNode(node.id, node.ip, node.port);

  int distanceTo(ByteString nid) {
    for (var i = 0; i < id.length; ++i) {
      var diff = id[i] ^ nid[i];
      if (diff == 0) continue;
      return (id.length - i - 1) * 8 + diff.toRadixString(2).length;
    }
    return 0;
  }

  @override
  String toString() => 'KNode(id=$id, addr=${ip.address}:$port)';
}

class KrpcError {
  final int code;
  final String reason;
  KrpcError(this.code, this.reason);

  @override
  String toString() => 'KrpcError($code:$reason)';
}

class Krpc {
  final ByteString id;
  final nodes = DoubleLinkedQueue();
  RawDatagramSocket? _socket;
  final _pending = <int, Completer>{};
  int _tid = 0;
  final _buckets = <int, DoubleLinkedQueue<KNode>>{};
  final info_hashs = <ByteString>[];

  final List<Uri> _defaultBootstrapNodes = [
    Uri(host: 'router.bittorrent.com', port: 6881),
    Uri(host: 'router.utorrent.com', port: 6881),
    Uri(host: 'dht.transmissionbt.com', port: 6881)
  ];

  Krpc({ByteString? id}) : id = id ?? ByteString.rand(20);

  Future bootstrap() async {
    await start();
    _defaultBootstrapNodes.forEach((url) {
      addBootstrapNode(url);
    });
  }

  Future<bool> addNode(KNode node) async {
    final distance = node.distanceTo(id);
    _buckets[distance] ??= DoubleLinkedQueue();
    final bucket = _buckets[distance]!;
    final oldNode = bucket.firstWhere((e) => e.distanceTo(node.id) == 0,
        orElse: () => node);
    if (oldNode != node) bucket.remove(oldNode);
    if (bucket.length < 20) {
      bucket.add(node);
      return true;
    } else {
      final firstNode = bucket.removeFirst();
      if (DateTime.now().millisecondsSinceEpoch - firstNode.timestamp <
          15 * 60 * 1000) {
        bucket.add(KNode.clone(firstNode));
      } else {
        try {
          final rsp = await ping(firstNode.ip, firstNode.port);
          if (firstNode.distanceTo(rsp['id']) == 0) {
            bucket.add(KNode.clone(firstNode));
          } else {
            throw KrpcError(203, 'Protocol Error: invalid arguments');
          }
        } catch (e) {
          return addNode(node);
        }
      }
    }
    return false;
  }

  Future<RawDatagramSocket> start([InternetAddress? host, int port = 0]) async {
    _stopSocket(_socket);
    final socket =
        await RawDatagramSocket.bind(host ?? InternetAddress.anyIPv4, port);
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final data = socket.receive()?.data;
        if (data == null) return;
        final resp = Bencode.decode(data);
        if (!(resp is Map)) return;
        final type = resp['y'];
        if (!(type is ByteString) || type.string != 'r') {
          print('<-- $resp');
          return;
        }
        final pending = _pending.remove(resp['t']?.toInt());
        if (pending == null) return;
        try {
          if (resp['r'] is Map) {
            pending.complete(resp['r']);
          } else {
            pending.completeError(KrpcError(resp['e'][0], resp['e'][1].string));
          }
        } catch (e) {
          pending.completeError(KrpcError(403, 'Invalid Data'));
        }
      },
      onError: (e) {
        _stopSocket(socket);
        start(host, port);
      },
      onDone: () => _stopSocket(socket),
    );
    _socket = socket;
    return socket;
  }

  Future<Map> _send(
      String type, Map data, InternetAddress address, int port) async {
    if (_socket == null) throw 'socket closed';
    final rand = Random();
    while (_pending.length > 8) {
      await Future.delayed(Duration(milliseconds: rand.nextInt(100)));
    }
    while (_pending[_tid] != null) {
      _tid++;
      _tid %= 0xffff;
      await Future.delayed(Duration.zero);
    }
    final tid = _tid;
    final completer = Completer<Map>();
    _pending[tid] = completer;
    print('-->$type($tid):$data');
    _socket!.send(
        Bencode.encode({
          't': ByteString.int(tid, 2),
          'y': 'q',
          'q': type,
          'a': data,
        }),
        address,
        port);
    return completer.future.timeout(Duration(seconds: 15)).whenComplete(() {
      if (_pending[tid] == completer) _pending.remove(tid);
    });
  }

  void addBootstrapNode(Uri url) async {
    try {
      final ip = InternetAddress.tryParse(url.host);
      final ips = ip != null ? [ip] : await InternetAddress.lookup(url.host);
      ips.forEach((ip) async {
        if (ip.type == InternetAddressType.IPv4) {
          try {
            _processNodes((await findNode(ip, url.port))['nodes']);
          } catch (e) {
            print(e);
          }
        }
      });
    } catch (e) {
      print(e);
    }
  }

  Future<Map> findNode(
    InternetAddress address,
    int port, [
    ByteString? target,
  ]) =>
      _send(
          'find_node',
          {
            'id': id,
            'target': target ?? id,
          },
          address,
          port);

  Future<Map> ping(
    InternetAddress address,
    int port,
  ) =>
      _send(
          'ping',
          {
            'id': id,
          },
          address,
          port);

  Future<Map> get_peers(
    InternetAddress address,
    int port,
    ByteString info_hash,
  ) =>
      _send(
          'get_peers',
          {
            'id': id,
            'info_hash': info_hash,
          },
          address,
          port);

  Future<Map> announce_peer(
    InternetAddress address,
    int port,
    ByteString info_hash,
  ) =>
      _send(
          'announce_peer',
          {
            'id': id,
            'info_hash': info_hash,
          },
          address,
          port);

  void _processNodes(ByteString nodes) {
    // final nodes = rsp['nodes'];
    if (!(nodes is ByteString) || nodes.length % 26 != 0) return;
    List.generate(
        nodes.length ~/ 26,
        (i) => KNode(
              ByteString(nodes.bytes.sublist(i * 26, i * 26 + 20)),
              InternetAddress.fromRawAddress(Uint8List.fromList(
                  nodes.bytes.sublist(i * 26 + 20, i * 26 + 24))),
              ByteString(nodes.bytes.sublist(i * 26 + 24, i * 26 + 26)).toInt(),
            )).forEach((node) => addNode(node).then((nodeAdded) {
          if (!nodeAdded) return;
          info_hashs.forEach((hash) async {
            try {
              _processGetPeers(hash, await get_peers(node.ip, node.port, hash));
            } catch (e) {
              print(e);
            }
          });
          findNode(node.ip, node.port, node.id).then(
            (n) => _processNodes(n['nodes']),
            onError: (_) {},
          );
        }));
    // print(_buckets.entries.map((e) => '${e.key}[${e.value.length}]'));
  }

  void _processGetPeers(ByteString hash, Map rsp) {
    // if (rsp['nodes'] is ByteString) {
    //   _processNodes(rsp['nodes']);
    // }
    // final peers = rsp['values'];
    // if (!(peers is List)) return;
    // peers.forEach((peerData) async {
    //   if (!(peerData is ByteString) || peerData.bytes.length != 6) return;
    //   final peer = Peer(
    //       InternetAddress.fromRawAddress(
    //           Uint8List.fromList(peerData.bytes.sublist(0, 4))),
    //       ByteString(peerData.bytes.sublist(4, 6)).toInt());
    //   try {
    //     await peer.handshake(hash, ByteString.rand(20));
    //   } catch (e) {
    //     // print(e);
    //   }
    // });
  }

  void _stopSocket(RawDatagramSocket? socket) {
    if (socket == null) return;
    socket.close();
  }
}
