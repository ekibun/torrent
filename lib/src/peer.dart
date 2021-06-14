import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';

const protocol = 'BitTorrent protocol';

class Peer {
  final InternetAddress ip;
  final int port;
  Socket? _socket;
  final _buffer = <int>[];
  ByteString? id;
  ByteString? reserved;
  ByteString? localId;
  DateTime _lastActive = DateTime.now();
  bool _amChoking = true;
  bool _amInterested = false;
  bool _isChoking = false;
  bool _isInterested = false;
  final _handler = <int, bool Function(Uint8List)>{};

  Peer(this.ip, this.port);

  @override
  String toString() => 'Peer(addr=${ip.address}:$port)';

  bool _consume() {
    if (_buffer.length < 4) return false;
    final length = ByteString(_buffer.sublist(0, 4)).toInt();
    if (_buffer.length < length + 4) return false;
    final buffer = _buffer.sublist(4, length + 4);
    _buffer.removeRange(0, length + 4);
    if (length == 0) {
      _lastActive = DateTime.now();
    } else {
      final id = buffer[0];
      final data = buffer.sublist(1, length);
      // print('<--$id$data');
      final handler = _handler[id];
      if (handler != null && handler(Uint8List.fromList(data))) return true;
      switch (id) {
        case 0:
          _isChoking = true;
          break;
        case 1:
          _isChoking = false;
          break;
        case 2:
          _isInterested = true;
          break;
        case 3:
          _isInterested = false;
      }
    }

    return true;
  }

  void choke() {
    _amChoking = true;
    _sendPacket(0);
  }

  void unchoke() {
    _amChoking = false;
    _sendPacket(1);
  }

  void interested() {
    _amInterested = true;
    _sendPacket(2);
  }

  void notinterested() {
    _amInterested = false;
    _sendPacket(3);
  }

  void _sendPacket(int id, [List<int>? data]) {
    final socket = _socket;
    if (socket == null) throw 'have not handshake';
    print('-->$id$data');
    socket.add(<int>[...ByteString.int((data?.length ?? 0) + 1, 4).bytes, id]);
    if (data != null) socket.add(data);
  }

  Future<Map> sendExtHandshake(Map m) {
    final completer = Completer<Map>();
    _handler[20] = (data) {
      try {
        _handler.remove(20);
        if (data[0] != 0) throw 'not handshake response';
        completer.complete(Bencode.decode(data.sublist(1)));
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
      return true;
    };
    _sendPacket(20, [
      0,
      ...ByteString(Bencode.encode({'m': m})).bytes,
    ]);
    return completer.future;
  }

  Future<Map> getMetaData() async {
    const metaDataPieceSize = 16 * 1024;
    final rsp = await sendExtHandshake({
      'ut_metadata': 0,
    });
    print(rsp);
    final metaDataSize = rsp['metadata_size'] ?? 0;
    final utMetaData = rsp['m']?['ut_metadata'] ?? 0;
    if (metaDataSize == 0 || utMetaData == 0) throw 'no metadata';
    final metaDataPieceLength = (metaDataSize / metaDataPieceSize).ceil();
    final pieceCompleter =
        List.generate(metaDataPieceLength, (index) => Completer());
    final metaDataBuffer = Uint8List(metaDataSize);
    _handler[20] = (data) {
      try {
        print(data[0]);
        final scanner = BencodeScanner(data.sublist(1));
        final res = scanner.next();
        if (!(res is Map) || res['msg_type'] != 1) return false;
        final int piece = res['piece'];
        print('complete ${piece + 1}/$metaDataPieceLength');
        final completer = pieceCompleter[piece];
        metaDataBuffer.setAll(
            piece * metaDataPieceSize, data.sublist(scanner.pos + 1));
        completer.complete();
        return true;
      } catch (e, stack) {
        pieceCompleter.forEach((c) {
          if (!c.isCompleted) c.completeError(e, stack);
        });
      }
      return false;
    };

    for (var piece = 0; piece < metaDataPieceLength; piece++) {
      _sendPacket(20, [
        utMetaData,
        ...ByteString(Bencode.encode({'msg_type': 0, 'piece': piece})).bytes,
      ]);
    }
    return Future.wait(pieceCompleter.map((c) {
      return c.future;
    })).then((value) => Bencode.decode(metaDataBuffer));
  }

  Future<ByteString> handshake(ByteString infoHash, ByteString peerId) async {
    localId = peerId;
    await _socket?.close();
    final completer = Completer<ByteString>();
    final socket = await Socket.connect(
      ip,
      port,
      timeout: Duration(seconds: 30),
    );
    socket.handleError((err, stack) {
      print('peer netErr: $err');
    }).listen((data) async {
      try {
        _buffer.addAll(data);
        if (!completer.isCompleted) {
          final protocolOffset = 1 + protocol.length;
          if (_buffer.length < protocolOffset + 28) return;
          if (_buffer[0] != protocol.length ||
              ByteString(_buffer.sublist(1, 1 + protocol.length)).string !=
                  protocol) {
            // ignore: unawaited_futures
            socket.close();
            completer.completeError('bad handshake response');
            throw 'bad handshake response';
          }
          reserved =
              ByteString(data.sublist(protocolOffset, protocolOffset + 8));
          id = ByteString(
              data.sublist(protocolOffset + 28, protocolOffset + 48));
          _buffer.removeRange(0, protocolOffset + 48);
          completer.complete(reserved);
          await Future.delayed(Duration.zero);
        }
        while (_consume()) {}
      } catch (e) {
        print(e);
      }
    }).onError((err, stack) {
      print('peer Err: $err');
    });
    // ignore: unawaited_futures
    socket.done.onError((err, stack) {
      print('peer close: $err');
    });
    _socket = socket;
    print('connected $this');
    socket.add(<int>[
      protocol.length,
      ...ByteString.str(protocol).bytes,
      ...ByteString.str('\x00\x00\x00\x00\x00\x10\x00\x00').bytes, // bep-10
      ...infoHash.bytes,
      ...peerId.bytes,
    ]);
    return completer.future;
  }
}
