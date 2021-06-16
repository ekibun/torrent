import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bep/bep0003.dart';
import 'package:torrent/src/bep/bep0010.dart';
import 'package:torrent/src/socket.dart';
import 'package:torrent/src/torrent.dart';

const _EXTENDED_METADATA_ID = 'ut_metadata';

mixin PeerBep0009<S extends PeerSocket> on PeerBep0010<S> {
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
    const metaDataPieceSize = PIECE_SIZE;
    final metaDataPieceLength = (metaDataSize / metaDataPieceSize).ceil();
    final metaDataBuffer = Uint8List(metaDataSize);
    for (var pid = 0; pid < metaDataPieceLength; ++pid) {
      final completer = Completer<Uint8List>();
      final oldCompleter = _pending[pid];
      if (oldCompleter?.isCompleted == false) {
        oldCompleter!.completeError(SocketException('cancel'));
      }
      _pending[pid] = completer;
      sendExtendMessage(
          _EXTENDED_METADATA_ID, Bencode.encode({'msg_type': 0, 'piece': pid}));
      metaDataBuffer.setAll(pid * metaDataPieceSize, await completer.future);
    }
    if (Torrent.parseInfoHash(metaDataBuffer).string != task.infoHash.string) {
      throw SocketException('infohash not matched');
    }
    return metaDataBuffer;
  }
}
