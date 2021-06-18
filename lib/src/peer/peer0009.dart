part of 'package:torrent/torrent.dart';

mixin _Peer0009 on _Peer0010 {
  static const _EXTENDED_METADATA_ID = 'ut_metadata';

  int metaDataSize = 0;

  final _pendingMetaData = <int, Completer<Uint8List>>{};

  @override
  Map<String, void Function(Uint8List)> get _onExtendMessage =>
      super._onExtendMessage
        ..[_EXTENDED_METADATA_ID] = (data) {
          final scanner = BencodeScanner(data);
          final message = scanner.next();
          if (!(message is Map)) throw SocketException('bad message');
          final type = message['msg_type'];
          if (type == 0) {
            // request
            return;
          }
          final completer = _pendingMetaData.remove(message['piece']);
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
  void _onExtendHandshake(Map message) {
    metaDataSize = message['metadata_size'] ?? metaDataSize;
    super._onExtendHandshake(message);
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
      final oldCompleter = _pendingMetaData[i];
      if (oldCompleter?.isCompleted == false) {
        oldCompleter!.completeError(SocketException('cancel'));
      }
      _pendingMetaData[i] = completer;
      _sendExtendMessage(
          _EXTENDED_METADATA_ID, Bencode.encode({'msg_type': 0, 'piece': i}));
      final data = await completer.future;
      if (signal?.isCompleted != false) throw 'cancel';
      metaDataBuffer.setAll(i * BLOCK_SIZE, data);
    }
    return metaDataBuffer;
  }
}
