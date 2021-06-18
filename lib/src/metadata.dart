part of 'package:torrent/torrent.dart';

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

class MetaData {
  final String name;
  final List<TorrentFile> files;
  final int pieceLength;
  final List<ByteString> pieces;
  final int length;
  final Map _raw;

  int get pieceCount => pieces.length;

  @override
  String toString() => 'MetaData($name)';

  int pieceSize(int index) => min(pieceLength, length - index * pieceLength);

  int blocksInPiece(int index) => (pieceSize(index) / BLOCK_SIZE).ceil();

  int blockSize(int index, int block) =>
      min(BLOCK_SIZE, pieceSize(index) - BLOCK_SIZE * block);

  MetaData._(
    this._raw,
    this.name,
    this.files,
    this.pieceLength,
    this.pieces,
  )   : length = files.map((e) => e.length).reduce((a, b) => a + b),
        infoHash = parseInfoHash(Bencode.encode(_raw));

  static MetaData fromMap(Map info) {
    final torrentFiles = <TorrentFile>[];
    final files = info['files'];
    final name = info['name'].utf8;
    if (files is List) {
      var offset = 0;
      torrentFiles.addAll(files.map((file) {
        int length = file['length'];
        offset += length;
        return TorrentFile(List<String>.from(file['path'].map((b) => b.utf8)),
            length, offset - length);
      }));
    } else {
      torrentFiles.add(TorrentFile([], info['length']));
    }
    final Uint8List pieces = info['pieces'].bytes;
    return MetaData._(
        info,
        name,
        torrentFiles,
        info['piece length'],
        List.generate(
          pieces.length ~/ 20,
          (i) => ByteString(pieces.sublist(20 * i, 20 * i + 20)),
        ));
  }

  final ByteString infoHash;

  static ByteString parseInfoHash(Uint8List info) =>
      ByteString(sha1.convert(info).bytes);

  Map toMap() => _raw;
}
