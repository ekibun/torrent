part of 'package:torrent/torrent.dart';

mixin _Peer0006 on _Peer0003 {
  static const OP_HAVE_ALL = 0x0E;
  static const OP_HAVE_NONE = 0x0F;
  static const OP_SUGGEST_PIECE = 0x0D;
  static const OP_REJECT_REQUEST = 0x10;
  static const OP_ALLOWED_FAST = 0x11;

  @override
  Uint8List get _selfReserved => super._selfReserved..[7] |= 0x04;

  bool get isSupportedFastExtension => (reserved?[7] ?? 0) & 0x04 != 0;

  @override
  void _onMessage(_PeerManager task, int op, Uint8List data) {
    switch (op) {
      case OP_HAVE_ALL:
        bitfield.haveAll = true;
        return;
      case OP_HAVE_NONE:
        bitfield.haveAll = false;
        bitfield.bytes = Uint8List(0);
        return;
      case OP_SUGGEST_PIECE:
        return;
      case OP_REJECT_REQUEST:
        return;
      case OP_ALLOWED_FAST:
        return;
    }
    return super._onMessage(task, op, data);
  }

  @override
  void _onRequestError(_BlockRequest req, error, stack) {
    if (error == 'cancel') return;
    if (isSupportedFastExtension) {
      sendRejectRequest(req.index, req.offset, req.length);
    }
  }

  void sendHaveAll() {
    sendPacket(OP_HAVE_ALL);
  }

  void sendHaveNone() {
    sendPacket(OP_HAVE_NONE);
  }

  void sendSuggestPiece(int index) {
    sendPacket(OP_SUGGEST_PIECE, ByteString.int(index, 4).bytes);
  }

  void sendRejectRequest(int index, int offset, int length) {
    sendPacket(OP_REJECT_REQUEST, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(offset, 4).bytes,
      ...ByteString.int(length, 4).bytes,
    ]);
  }

  void sendAllowedFast(int index) {
    sendPacket(OP_SUGGEST_PIECE, ByteString.int(index, 4).bytes);
  }
}
