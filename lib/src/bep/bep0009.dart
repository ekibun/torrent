import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bep/bep0003.dart';
import 'package:torrent/src/bep/bep0010.dart';
import 'package:torrent/src/torrent.dart';

mixin PeerBep0009 on PeerBep0010 {
  static const _EXTENDED_METADATA_ID = 'ut_metadata';

  int metaDataSize = 0;

  final _pending = <int, Completer<Uint8List>>{};

  @override
  Map<String, void Function(Uint8List)> get onExtendMessage =>
      super.onExtendMessage
        ..[_EXTENDED_METADATA_ID] = (data) {
          final scanner = BencodeScanner(data);
          final message = scanner.next();
          if (!(message is Map)) throw SocketException('bad message');
          final type = message['msg_type'];
          if (type == 0) {
            // request
            return;
          }
          final completer = _pending.remove(message['piece']);
          if (completer?.isCompleted == false) {
            if (type == 1) {
              completer?.complete(data.sublist(scanner.pos));
            } else {
              completer?.completeError(
                  SocketException('$this reject request metadata'));
            }
          }
        };

  @override
  void onExtendHandshake(Map message) {
    metaDataSize = message['metadata_size'] ?? metaDataSize;
    super.onExtendHandshake(message);
  }

  Future<Uint8List> getMetadata([Completer? signal]) async {
    await extendHandshaked;
    if (metaDataSize == 0) {
      throw SocketException('$this has no metadata');
    }
    final metaDataPieceLength = (metaDataSize / BLOCK_SIZE).ceil();
    final metaDataBuffer = Uint8List(metaDataSize);
    for (var i = 0; i < metaDataPieceLength; ++i) {
      final completer = Completer<Uint8List>();
      final oldCompleter = _pending[i];
      if (oldCompleter?.isCompleted == false) {
        oldCompleter!.completeError(SocketException('cancel'));
      }
      _pending[i] = completer;
      sendExtendMessage(
          _EXTENDED_METADATA_ID, Bencode.encode({'msg_type': 0, 'piece': i}));
      final data = await completer.future;
      metaDataBuffer.setAll(i * BLOCK_SIZE, data);
    }
    if (Torrent.parseInfoHash(metaDataBuffer).string != task?.infoHash.string) {
      throw SocketException('infohash not matched');
    }
    return metaDataBuffer;
  }
}
