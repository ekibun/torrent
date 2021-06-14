import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';

const protocol = 'BitTorrent protocol';

class PeerInfo {
  final InternetAddress ip;
  final int port;
  final _buffer = <int>[];
  PeerInfo(this.ip, this.port);

  @override
  String toString() => 'PeerInfo(${ip.address}:$port)';

  Future<Peer> handshake(ByteString infoHash, ByteString peerId) {
    final completer = Completer<Peer>();
    Peer? peer;
    Socket.connect(
      ip,
      port,
      timeout: Duration(seconds: 30),
    ).then((socket) {
      socket.handleError((_) {}).listen((data) {
        if (!completer.isCompleted) {
          _buffer.addAll(data);
          try {
            final protocolOffset = 1 + protocol.length;
            if (_buffer.length < protocolOffset + 28) return;
            if (_buffer[0] != protocol.length ||
                ByteString(_buffer.sublist(1, 1 + protocol.length)).string !=
                    protocol) {
              throw 'bad handshake response';
            }
            final reserved =
                ByteString(data.sublist(protocolOffset, protocolOffset + 8));
            final id = ByteString(
                data.sublist(protocolOffset + 28, protocolOffset + 48));
            _buffer.removeRange(0, protocolOffset + 48);
            peer = Peer._(socket, reserved, id, _buffer);
            completer.complete(peer);
          } catch (e) {
            completer.completeError('bad handshake response');
            socket.close();
          }
        } else {
          peer?._buffer.addAll(data);
          peer?._consumeData();
        }
      });
      socket.done.onError((err, stack) {
        print('peer close: $err');
      }).whenComplete(() {
        peer?.close();
        if (!completer.isCompleted) completer.completeError('socket closed');
      });
      socket.add(<int>[
        protocol.length,
        ...ByteString.str(protocol).bytes,
        ...ByteString.str('\x00\x00\x00\x00\x00\x10\x00\x00').bytes, // bep-10
        ...infoHash.bytes,
        ...peerId.bytes,
      ]);
    }).onError((err, stack) {
      completer.completeError(
          err ?? SocketException('Cannot create connection'), stack);
    });
    return completer.future;
  }
}

class Peer {
  final Socket _socket;
  final List<int> _buffer;
  final ByteString id;
  final ByteString reserved;

  void Function()? onClose;

  InternetAddress get ip => _socket.address;
  int get port => _socket.port;

  DateTime _lastActive = DateTime.now();
  bool _amChoking = true;
  bool _amInterested = false;
  bool _isChoking = false;
  bool _isInterested = false;
  final _pending = <int, Completer<Uint8List>>{};

  Peer._(this._socket, this.reserved, this.id, this._buffer) {
    if (_buffer.isNotEmpty) Future.delayed(Duration.zero, _consumeData);
    // Timer.periodic(Duration.hoursPerDay, (timer) { })
  }

  Future close() {
    onClose?.call();
    return _socket.close();
  }

  @override
  String toString() => 'Peer(${_socket.address.address}:${_socket.port})';

  void _consumeData() {
    while (true) {
      if (_buffer.length < 4) break;
      final length = ByteString(_buffer.sublist(0, 4)).toInt();
      if (_buffer.length < length + 4) break;
      final buffer = _buffer.sublist(4, length + 4);
      _buffer.removeRange(0, length + 4);
      if (length == 0) {
        _lastActive = DateTime.now();
      } else {
        final id = buffer[0];
        final data = buffer.sublist(1, length);
        print('<--$id[len=${data.length}]');
        final pending = _pending.remove(id);
        if (pending != null) {
          pending.complete(Uint8List.fromList(data));
          continue;
        }
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
    }
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
    print('-->$id[len=${data?.length ?? 0}]');
    _socket.add(<int>[...ByteString.int((data?.length ?? 0) + 1, 4).bytes, id]);
    if (data != null) _socket.add(data);
  }

  Future<Uint8List> sendPacket(int id, [List<int>? data]) {
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    _sendPacket(id, data ?? []);
    return completer.future;
  }
}
