import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bep/bep0010.dart';

mixin PeerBep0054 on PeerBep0010 {
  static const _EXTENDED_DONTHAVE_ID = 'lt_donthave';

  @override
  Map<String, void Function(Uint8List)> get onExtendMessage =>
      super.onExtendMessage
        ..[_EXTENDED_DONTHAVE_ID] = (data) {
          bitfield[ByteString(data).toInt()] = false;
        };

  void sendDontHAve(int index) {
    sendExtendMessage(_EXTENDED_DONTHAVE_ID, ByteString.int(index, 4).bytes);
  }
}
