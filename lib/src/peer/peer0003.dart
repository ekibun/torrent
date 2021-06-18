part of 'package:torrent/torrent.dart';

abstract class _Peer0003 {
  static const OP_CHOKE = 0;
  static const OP_UNCHOKE = 1;
  static const OP_INTERESTED = 2;
  static const OP_NOT_INTERESTED = 3;
  static const OP_HAVE = 4;
  static const OP_BITFIELD = 5;
  static const OP_REQUEST = 6;
  static const OP_PIECE = 7;
  static const OP_CANCEL = 8;

  final InternetAddress ip;
  final int port;
  _Peer0003(this.ip, this.port);

  Socket? _socket;
  ByteString? id;
  ByteString? reserved;

  final Bitfield bitfield = Bitfield();
  DateTime _lastActive = DateTime.now();
  bool _amChoking = true;
  bool _amInterested = false;
  bool _isChoking = true;
  bool _isInterested = false;

  bool get isConnected => _handshakeCompleter?.isCompleted ?? false;

  bool get amChoking => _amChoking;
  bool get amInterested => _amInterested;
  bool get isChoking => _isChoking;
  bool get isInterested => _isInterested;

  final _pendingBlocks = <_BlockRequest>{};

  Uint8List get _selfReserved => Uint8List(8);

  Future close() async {
    return _socket?.close();
  }

  Completer<Socket>? _handshakeCompleter;

  void _onPiece(int index, int offset, Uint8List data) {
    _pendingBlocks.removeWhere(
        (pending) => pending.index == index && pending.offset == offset);
  }

  void _onHandshaked() {}

  Future<Socket> _handshake(
    _PeerManager task,
  ) {
    if (_handshakeCompleter != null) return _handshakeCompleter!.future;
    final handshakeCompleter = Completer<Socket>();
    _handshakeCompleter = handshakeCompleter;
    final buffer = <int>[];
    Socket.connect(ip, port).then((socket) {
      _socket = socket;
      final consumeData = () {
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
            _onMessage(task, id, Uint8List.fromList(data));
          }
        }
      };
      socket.handleError(task._emitError).listen((data) async {
        buffer.addAll(data);
        try {
          if (reserved != null) {
            return consumeData();
          }
          if (buffer.length < BITTORRENT_PROTOCOL.length + 49) return;
          if (buffer[0] != BITTORRENT_PROTOCOL.length ||
              ByteString(buffer.sublist(1, 1 + BITTORRENT_PROTOCOL.length))
                      .utf8 !=
                  BITTORRENT_PROTOCOL) {
            throw 'Bad handshake response';
          }
          reserved = ByteString(data.sublist(
              BITTORRENT_PROTOCOL.length + 1, BITTORRENT_PROTOCOL.length + 9));
          id = ByteString(data.sublist(BITTORRENT_PROTOCOL.length + 29,
              BITTORRENT_PROTOCOL.length + 49));
          buffer.removeRange(0, BITTORRENT_PROTOCOL.length + 49);
          _onHandshaked();
          handshakeCompleter.complete(socket);
          await Future.delayed(Duration.zero);
          consumeData();
        } catch (error, stack) {
          task._emitError(error, stack);
          await socket.close();
        }
      });
      socket.add(<int>[
        BITTORRENT_PROTOCOL.length,
        ...ByteString.str(BITTORRENT_PROTOCOL).bytes,
        ..._selfReserved,
        ...task.infoHash.bytes,
        ...task.peerId.bytes,
      ]);
      socket.done.catchError(task._emitError).whenComplete(() {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.completeError('Socket closed');
        }
        if (_handshakeCompleter == handshakeCompleter) {
          _handshakeCompleter = null;
        }
      });
    }).catchError((err, stack) {
      handshakeCompleter.completeError(err, stack);
    });
    return handshakeCompleter.future;
  }

  void _onMessage(_PeerManager task, int op, Uint8List data) {
    switch (op) {
      case OP_CHOKE:
        _isChoking = true;
        return;
      case OP_UNCHOKE:
        _isChoking = false;
        return;
      case OP_INTERESTED:
        _isInterested = true;
        return;
      case OP_NOT_INTERESTED:
        _isInterested = false;
        return;
      case OP_HAVE:
        bitfield[ByteString(data).toInt()] = true;
        return;
      case OP_BITFIELD:
        bitfield.bytes = data;
        return;
      case OP_REQUEST:
        return;
      case OP_PIECE:
        final index = ByteString(data.sublist(0, 4)).toInt();
        final offset = ByteString(data.sublist(4, 8)).toInt();
        final buffer = data.sublist(8);
        _onPiece(index, offset, buffer);
        task._onPiece(index, offset, buffer);
        return;
      case OP_CANCEL:
        return;
    }
    throw UnimplementedError('Message id $id not supported');
  }

  void sendPacket([int? op, List<int>? data]) {
    final post = List<int>.from(
        ByteString.int((data?.length ?? 0) + (op == null ? 0 : 1), 4).bytes);
    if (op != null) post.add(op);
    if (data != null) post.addAll(data);
    try {
      _socket!.add(post);
    } catch (_) {}
  }

  void keepalive() {
    sendPacket();
  }

  void choke() {
    _amChoking = true;
    sendPacket(OP_CHOKE);
  }

  void unchoke() {
    _amChoking = false;
    sendPacket(OP_UNCHOKE);
  }

  void interested() {
    _amInterested = true;
    sendPacket(OP_INTERESTED);
  }

  void notinterested() {
    _amInterested = false;
    sendPacket(OP_NOT_INTERESTED);
  }

  void sendHave(int index) {
    sendPacket(OP_HAVE, ByteString.int(index, 4).bytes);
  }

  void sendBitfield() {
    sendPacket(OP_BITFIELD, bitfield.bytes);
  }

  void request(int index, int offset, int length) {
    _pendingBlocks.add(_BlockRequest(index, offset, length));
    sendPacket(OP_REQUEST, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...ByteString.int(length, 4).bytes,
    ]);
  }

  void sendPiece(int index, int offset, List<int> data) {
    sendPacket(OP_PIECE, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...data,
    ]);
  }

  void sendCancel(int index, int offset, int length) {
    sendPacket(OP_CANCEL, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...ByteString.int(length, 4).bytes,
    ]);
  }
}
