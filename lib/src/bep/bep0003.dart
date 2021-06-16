import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bitfield.dart';
import 'package:torrent/src/socket.dart';
import 'package:torrent/src/task.dart';

const PIECE_SIZE = 16 * 1024;
const BITTORRENT_PROTOCOL = 'BitTorrent protocol';

abstract class PeerBep0003 {
  final InternetAddress ip;
  final int port;
  PeerBep0003(this.ip, this.port);

  ByteString? id;
  ByteString? reserved;
  PeerSocket? _socket;
  Timer? _keepAliveTimer;
  TorrentTask? task;

  final Completer _handshakeCompleter = Completer();

  Uint8List get selfReserved => Uint8List(8);

  @override
  String toString() => 'Peer(${ip.address}:$port)';

  void onHandshaked() {
    _keepAliveTimer = Timer.periodic(Duration(seconds: 20), (_) {
      if (DateTime.now().difference(_lastActive).inMinutes > 2) {
        close();
      } else {
        keepalive();
      }
    });
  }

  Future handshake(
    Future<PeerSocket> Function(InternetAddress, int) connector,
    TorrentTask task,
  ) {
    this.task = task;
    if (_handshakeCompleter.isCompleted) {
      throw SocketException('$this already connected');
    }

    final buffer = <int>[];
    connector(ip, port).then((socket) {
      _socket = socket;
      socket.onData = (data) {
        buffer.addAll(data);
        if (_handshakeCompleter.isCompleted) {
          return consumeData(buffer);
        }
        if (buffer.length < BITTORRENT_PROTOCOL.length + 49) return;
        if (buffer[0] != BITTORRENT_PROTOCOL.length ||
            ByteString(buffer.sublist(1, 1 + BITTORRENT_PROTOCOL.length))
                    .string !=
                BITTORRENT_PROTOCOL) {
          throw SocketException('Bad handshake response');
        }
        reserved = ByteString(data.sublist(
            BITTORRENT_PROTOCOL.length + 1, BITTORRENT_PROTOCOL.length + 9));
        id = ByteString(data.sublist(
            BITTORRENT_PROTOCOL.length + 29, BITTORRENT_PROTOCOL.length + 49));
        buffer.removeRange(0, BITTORRENT_PROTOCOL.length + 49);
        Future.delayed(Duration.zero, () => consumeData(buffer));
        _handshakeCompleter.complete();
        onHandshaked();
      };
      socket.add(<int>[
        BITTORRENT_PROTOCOL.length,
        ...ByteString.str(BITTORRENT_PROTOCOL).bytes,
        ...selfReserved,
        ...task.infoHash.bytes,
        ...task.peerId.bytes,
      ]);
    }).catchError((e, stack) {
      if (!_handshakeCompleter.isCompleted) {
        _handshakeCompleter.completeError(e, stack);
      }
    });
    return _handshakeCompleter.future;
  }

  Future close() async {
    _keepAliveTimer?.cancel();
    return _socket?.close();
  }

  void sendPacket([int? id, List<int>? data]) {
    final post = List<int>.from(
        ByteString.int((data?.length ?? 0) + (id == null ? 0 : 1), 4).bytes);
    if (id != null) post.add(id);
    if (data != null) post.addAll(data);
    _socket?.add(post);
  }

  final Bitfield bitfield = Bitfield();
  DateTime _lastActive = DateTime.now();
  bool _amChoking = true;
  bool _amInterested = false;
  bool _isChoking = true;
  bool _isInterested = false;

  bool get amChoking => _amChoking;
  bool get amInterested => _amInterested;
  bool get isChoking => _isChoking;
  bool get isInterested => _isInterested;

  void consumeData(List<int> buffer) {
    while (true) {
      if (buffer.length < 4) break;
      final length = ByteString(buffer.sublist(0, 4)).toInt();
      if (buffer.length < length + 4) break;
      final messageData = buffer.sublist(4, length + 4);
      buffer.removeRange(0, length + 4);
      if (length == 0) {
        _lastActive = DateTime.now();
      } else {
        final id = messageData[0];
        final data = messageData.sublist(1, length);
        onMessage(id, Uint8List.fromList(data));
      }
    }
  }

  void onMessage(int id, Uint8List data) {
    switch (id) {
      case 0: // choke
        _isChoking = true;
        return;
      case 1: // unchoke
        _isChoking = false;
        return;
      case 2: // interested
        _isInterested = true;
        return;
      case 3: // not interested
        _isInterested = false;
        return;
      case 4: // have
        bitfield[ByteString(data).toInt()] = true;
        return;
      case 5: // bitfield
        bitfield.bytes = data;
        return;
      case 6: // request
        return;
      case 7: // piece
        final index = ByteString(data.sublist(0, 4)).toInt();
        final offset = ByteString(data.sublist(4, 8)).toInt();
        task?.onPiece.call(index, offset, data.sublist(8));
        return;
      case 8: // cancel
        return;
    }
    throw UnimplementedError('Message id $id not supported');
  }

  void keepalive() {
    sendPacket();
  }

  void choke() {
    _amChoking = true;
    sendPacket(0);
  }

  void unchoke() {
    _amChoking = false;
    sendPacket(1);
  }

  void interested() {
    _amInterested = true;
    sendPacket(2);
  }

  void notinterested() {
    _amInterested = false;
    sendPacket(3);
  }

  void sendHave(int index) {
    sendPacket(4, ByteString.int(index, 4).bytes);
  }

  void sendBitfield() {
    sendPacket(5, bitfield.bytes);
  }

  void request(int index, int offset, [int length = PIECE_SIZE]) {
    sendPacket(6, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...ByteString.int(length, 4).bytes,
    ]);
  }

  void sendPiece(int index, int offset, List<int> data) {
    sendPacket(7, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...data,
    ]);
  }

  void sendCancel(int index, int offset, int length) {
    sendPacket(8, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...ByteString.int(length, 4).bytes,
    ]);
  }
}
