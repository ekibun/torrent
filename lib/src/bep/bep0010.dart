import 'dart:async';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bep/bep0003.dart';

mixin PeerBep0010 on PeerBep0003 {
  static const OP_EXTENDED = 20;

  @override
  Uint8List get selfReserved => super.selfReserved..[5] |= 0x10;

  bool get isSupportedExtendMessage => (reserved?[5] ?? 0) & 0x10 != 0;

  Map<String, void Function(Uint8List)> get onExtendMessage => {};

  Map<String, int> _extendMessageId = {};
  final Completer _extendHandshakeCompleter = Completer();
  Future get extendHandshaked => _extendHandshakeCompleter.future;

  @override
  void onHandshaked() {
    extendHandshake().catchError((_) {});
    super.onHandshaked();
  }

  @override
  void onMessage(int op, Uint8List data) {
    if (op != OP_EXTENDED) return super.onMessage(op, data);
    final extId = data[0];
    if (extId == 0) {
      onExtendHandshake(Bencode.decode(data, 1));
    } else {
      onExtendMessage.entries.elementAt(extId - 1).value(data.sublist(1));
    }
  }

  void onExtendHandshake(Map message) {
    if (!_extendHandshakeCompleter.isCompleted) {
      _extendHandshakeCompleter.complete();
    }
    _extendMessageId = Map<String, int>.from(message['m'] ?? _extendMessageId);
  }

  void sendExtendMessage(String key, Uint8List payload) =>
      sendPacket(OP_EXTENDED, [
        _extendMessageId[key]!,
        ...payload,
      ]);

  Future extendHandshake() {
    var messageId = 0;
    sendPacket(OP_EXTENDED, [
      0,
      ...Bencode.encode(
          {'m': onExtendMessage.map((k, v) => MapEntry(k, ++messageId))})
    ]);
    return extendHandshaked;
  }
}
