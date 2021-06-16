import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bep/bep0003.dart';
import 'package:torrent/src/socket.dart';

mixin PeerInfoBep0010<S extends PeerSocket, P extends BasePeer>
    on BasePeerInfo<S, P> {
  @override
  Uint8List get reserved => super.reserved..[5] |= 0x10;
}

const EXTENDED_PROTOCOL = 20;

mixin PeerBep0010<S extends PeerSocket> on BasePeer<S> {
  Map<String, void Function(Uint8List)> get onExtendMessage => {};

  Map<String, int> _extendMessageId = {};
  final Completer _extendHandshakeCompleter = Completer();
  Future get extendHandshaked => _extendHandshakeCompleter.future;

  @override
  void onMessage(int id, Uint8List data) {
    if (id != EXTENDED_PROTOCOL) return super.onMessage(id, data);
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
      sendPacket(EXTENDED_PROTOCOL, [
        _extendMessageId[key]!,
        ...payload,
      ]);

  Future extendHandshake() {
    var messageId = 0;
    sendPacket(EXTENDED_PROTOCOL, [
      0,
      ...Bencode.encode(
          {'m': onExtendMessage.map((k, v) => MapEntry(k, ++messageId))})
    ]);
    return extendHandshaked;
  }

  bool get isSupportedExtendMessage => reserved[5] & 0x10 != 0;
}
