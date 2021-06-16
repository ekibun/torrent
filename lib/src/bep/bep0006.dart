import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bep/bep0003.dart';

mixin PeerBep0006 on PeerBep0003 {
  static const OP_HAVE_ALL = 0x0E;
  static const OP_HAVE_NONE = 0x0F;
  static const OP_SUGGEST_PIECE = 0x0D;
  static const OP_REJECT_REQUEST = 0x10;
  static const OP_ALLOWED_FAST = 0x11;
  
  @override
  Uint8List get selfReserved => super.selfReserved..[7] |= 0x04;

  bool get isSupportedExtendMessage => (reserved?[7] ?? 0) & 0x04 != 0;

  @override
  void onHandshaked() {
    super.onHandshaked();
    if (isSupportedExtendMessage) sendHaveNone();
  }

  @override
  void onMessage(int op, Uint8List data) {
    switch (op) {
      case PeerBep0003.OP_BITFIELD:
        bitfield.haveAll = false;
        break;
      case OP_HAVE_ALL:
        bitfield.haveAll = true;
        return;
      case OP_HAVE_NONE:
        bitfield.haveAll = false;
        return;
      case OP_SUGGEST_PIECE:
        return;
      case OP_REJECT_REQUEST:
        return;
      case OP_ALLOWED_FAST:
        return;
    }
    return super.onMessage(op, data);
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

  void sendRejectRequest(int index, int begin, int length) {
    sendPacket(OP_REJECT_REQUEST, [
      ...ByteString.int(index, 4).bytes,
      ...ByteString.int(begin, 4).bytes,
      ...ByteString.int(length, 4).bytes,
    ]);
  }

  void sendAllowedFast(int index) {
    sendPacket(OP_ALLOWED_FAST, ByteString.int(index, 4).bytes);
  }
}
