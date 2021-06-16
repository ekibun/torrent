import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bitfield.dart';
import 'package:torrent/src/socket.dart';
import 'package:torrent/src/task.dart';

const PIECE_SIZE = 16 * 1024;
const PROTOCOL = 'BitTorrent protocol';

abstract class BasePeerInfo<TSocket extends PeerSocket,
    TPeer extends BasePeer> {
  final InternetAddress ip;
  final int port;
  BasePeerInfo(this.ip, this.port);

  @override
  String toString() => 'PeerInfo(${ip.address}:$port)';

  Future<TSocket> connect();

  TPeer createPeer(
    TSocket socket,
    ByteString reserved,
    ByteString id,
    TorrentTask task,
  );

  Uint8List get reserved => Uint8List(8);
  Future<TPeer> handshake(TorrentTask task) {
    final completer = Completer<TPeer>();
    final buffer = <int>[];
    TPeer? peer;
    connect().then((socket) {
      socket.onData = (data) {
        buffer.addAll(data);
        if (completer.isCompleted) {
          return peer?.consumeData(buffer);
        }
        if (buffer.length < PROTOCOL.length + 49) return;
        if (buffer[0] != PROTOCOL.length ||
            ByteString(buffer.sublist(1, 1 + PROTOCOL.length)).string !=
                PROTOCOL) {
          throw SocketException('Bad handshake response');
        }
        final reserved =
            ByteString(data.sublist(PROTOCOL.length + 1, PROTOCOL.length + 9));
        final id = ByteString(
            data.sublist(PROTOCOL.length + 29, PROTOCOL.length + 49));
        buffer.removeRange(0, PROTOCOL.length + 49);
        peer = createPeer(socket, reserved, id, task);
        Future.delayed(Duration.zero, () => peer?.consumeData(buffer));
        completer.complete(peer);
      };
      socket.add(<int>[
        PROTOCOL.length,
        ...ByteString.str(PROTOCOL).bytes,
        ...ByteString.str('\x00\x00\x00\x00\x00\x10\x00\x00').bytes, // bep-10
        ...task.infoHash.bytes,
        ...task.peerId.bytes,
      ]);
    }).catchError((e, stack) {
      completer.completeError(e, stack);
    });
    return completer.future;
  }
}

abstract class BasePeer<TSocket extends PeerSocket> {
  final ByteString id;
  final ByteString reserved;
  final TorrentTask task;
  final TSocket _socket;
  Timer? _keepAliveTimer;
  // final _pending = <int, Completer<Uint8List>>{};

  InternetAddress get ip => _socket.address;
  int get port => _socket.port;

  @override
  String toString() => 'PeerInfo(${ip.address}:$port)';

  BasePeer(this.task, this.id, this.reserved, this._socket) {
    _keepAliveTimer = Timer.periodic(Duration(seconds: 20), (_) {
      if (DateTime.now().difference(_lastActive).inMinutes > 2) {
        close();
      } else {
        keepalive();
      }
    });
  }

  Future close() {
    task.peers.remove(this);
    _keepAliveTimer?.cancel();
    return _socket.close();
  }

  // Future<Uint8List> sendPacket(int id, [List<int>? data]) {
  //   final completer = Completer<Uint8List>();
  //   _pending[id] = completer;
  //   _sendPacket(id, data ?? []);
  //   return completer.future;
  // }

  void sendPacket([int? id, List<int>? data]) {
    final post = List<int>.from(
        ByteString.int((data?.length ?? 0) + (id == null ? 0 : 1), 4).bytes);
    if (id != null) post.add(id);
    if (data != null) post.addAll(data);
    _socket.add(post);
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
    // final pending = _pending.remove(id);
    // if (pending != null) {
    //   pending.complete(Uint8List.fromList(data));
    //   return;
    // }
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
        task.onPiece(index, offset, data.sublist(8));
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
