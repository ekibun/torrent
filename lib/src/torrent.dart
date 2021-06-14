import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:crypto/crypto.dart' show sha1;

class TorrentFile {
  List<String> path;
  int length;
  int offset;
  TorrentFile(
    this.path,
    this.length, [
    this.offset = 0,
  ]);

  @override
  String toString() =>
      'File(path=${path.join('/')}, len=$length, offset=$offset)';
}

class Torrent {
  final Map _raw;
  final List<TorrentFile> files;
  final List<String> announces;
  final int? creationDate;
  final String? createdBy;
  final int pieceLength;
  final Uint8List pieces;

  Torrent._(
    this._raw,
    this.files,
    this.announces,
    this.pieceLength,
    this.pieces, [
    this.creationDate,
    this.createdBy,
  ]);

  static Torrent parse(Map data) {
    final trackers = <String>[];
    final announceList = data['announce-list'];
    final announce = data['announce'];
    if (announceList is List) {
      for (var announces in announceList) {
        trackers
            .addAll(List.from(announces.map((announce) => announce.string)));
      }
    } else if (announce is ByteString) {
      trackers.add(announce.string);
    }
    final torrentFiles = <TorrentFile>[];
    final files = data['info']['files'];
    final name = data['info']['name'];
    if (files is List) {
      var offset = 0;
      torrentFiles.addAll(files.map((file) {
        int length = file['length'];
        offset += length;
        return TorrentFile(
            List<String>.from([name, ...file['path']].map((b) => b.string)),
            length,
            offset - length);
      }));
    } else {
      torrentFiles.add(TorrentFile([name.string], data['info']['length']));
    }
    return Torrent._(
      data,
      torrentFiles,
      trackers,
      data['info']['piece length'],
      data['info']['pieces'].bytes,
      data['creation date'],
      data['created by']?.string,
    );
  }

  Map get raw => _raw;
  ByteString get infoHash => parseInfoHash(Bencode.encode(_raw['info']));

  static ByteString parseInfoHash(Uint8List info) =>
      ByteString(sha1.convert(info).bytes);
}
