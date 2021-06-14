import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/task.dart';

const protocol = 'BitTorrent protocol';

const PIECE_SIZE = 16 * 1024;

class Bitfield {
  Uint8List _bytes = Uint8List(0);

  void _grow(int bitLength) {
    final byteLength = (bitLength / 8).ceil();
    if (_bytes.length < byteLength) {
      _bytes = Uint8List(byteLength)..setAll(0, _bytes);
    }
  }

  bool operator [](int index) {
    _grow(index);
    return _bytes[index >> 3] & (128 >> (index % 8)) != 0;
  }

  void operator []=(int index, bool bit) {
    _grow(index);
    final byteIndex = index >> 3;
    if (bit) {
      _bytes[byteIndex] |= (128 >> (index % 8));
    } else {
      _bytes[byteIndex] &= ~(128 >> (index % 8));
    }
  }
}

class PeerInfo {
  final InternetAddress ip;
  final int port;
  final _buffer = <int>[];
  PeerInfo(this.ip, this.port);

  @override
  String toString() => 'PeerInfo(${ip.address}:$port)';

  Future<Peer> handshake(TorrentTask task) {
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
            peer = Peer._(socket, reserved, id, _buffer, task);
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
        if (!completer.isCompleted) {
          completer.completeError(err ?? SocketException.closed(), stack);
        }
      }).whenComplete(() {
        peer?.close();
        if (!completer.isCompleted) completer.completeError('socket closed');
      });
      socket.add(<int>[
        protocol.length,
        ...ByteString.str(protocol).bytes,
        ...ByteString.str('\x00\x00\x00\x00\x00\x10\x00\x00').bytes, // bep-10
        ...task.infoHash.bytes,
        ...task.peerId.bytes,
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
  final TorrentTask _task;
  final Bitfield bitfield = Bitfield();
  Timer? _keepAliveTimer;

  InternetAddress get ip => _socket.address;
  int get port => _socket.port;

  DateTime _lastActive = DateTime.now();
  bool _amChoking = true;
  bool _amInterested = false;
  bool _isChoking = true;
  bool _isInterested = false;

  bool get amChoking => _amChoking;
  bool get amInterested => _amInterested;
  bool get isChoking => _isChoking;
  bool get isInterested => _isInterested;

  final _pending = <int, Completer<Uint8List>>{};

  Peer._(this._socket, this.reserved, this.id, this._buffer, this._task) {
    if (_buffer.isNotEmpty) Future.delayed(Duration.zero, _consumeData);
    _task.peers.add(this);
    _keepAliveTimer = Timer.periodic(Duration(seconds: 20), (_) {
      if (DateTime.now().difference(_lastActive).inMinutes > 2) {
        close();
      } else {
        keepalive();
      }
    });
  }

  Future close() {
    _task.peers.remove(this);
    _keepAliveTimer?.cancel();
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
        final pending = _pending.remove(id);
        if (pending != null) {
          pending.complete(Uint8List.fromList(data));
          continue;
        }
        switch (id) {
          case 0: // choke
            _isChoking = true;
            break;
          case 1: // unchoke
            _isChoking = false;
            break;
          case 2: // interested
            _isInterested = true;
            break;
          case 3: // not interested
            _isInterested = false;
            break;
          case 4: // have
            bitfield[ByteString(data).toInt()] = true;
            break;
          case 5: // bitfield
            bitfield._bytes = Uint8List.fromList(data);
            break;
          case 6: // request
            break;
          case 7: // piece
            final index = ByteString(data.sublist(0, 4)).toInt();
            final offset = ByteString(data.sublist(4, 8)).toInt();
            _task.onPiece(index, offset, data.sublist(8));
            break;
          case 8: // cancel
            break;
        }
      }
    }
  }

  void keepalive() {
    _socket.add(Uint8List(4));
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

  void sendHave(int index) {
    _sendPacket(4, ByteString.int(index, 4).bytes);
  }

  void sendBitfield() {
    _sendPacket(5, bitfield._bytes);
  }

  void request(int index, int offset, [int length = PIECE_SIZE]) {
    _sendPacket(6, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...ByteString.int(length, 4).bytes,
    ]);
  }

  void piece(int index, int offset, List<int> data) {
    _sendPacket(7, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...data,
    ]);
  }

  void cancel(int index, int offset, int length) {
    _sendPacket(8, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...ByteString.int(length, 4).bytes,
    ]);
  }

  void _sendPacket(int id, [List<int>? data]) {
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
