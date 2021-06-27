import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' show joinAll;
import 'package:torrent/torrent.dart';

abstract class TorrentStorage {
  Bitfield get bitfield;
  void writePiece(MetaData info, Piece piece);
  Future<Piece> getPiece(MetaData info, int index);

  void close(MetaData info);
}

class _File {
  final RandomAccessFile file;
  Completer? lock;

  _File._(this.file);

  static _File openFile(File file) {
    file.parent.createSync(recursive: true);
    return _File._(file.openSync(mode: FileMode.append));
  }
}

class FileTorrentStorage extends TorrentStorage {
  final String dir;
  final Bitfield _bitfield = Bitfield();

  FileTorrentStorage(this.dir);
  @override
  Bitfield get bitfield => _bitfield;

  final _files = <TorrentFile, _File>{};

  @override
  Future<Piece> getPiece(MetaData info, int index) async {
    if (!_bitfield[index]) throw 'Piece Not have';
    final offset = info.pieceLength * index;
    final length = info.pieceSize(index);
    final piece = Piece(index, length)..blocks.haveAll = true;
    var setOffset = 0;
    for (var file in info.files) {
      if (file.offset + file.length <= offset) continue;
      final diskfile = File(joinAll([dir, info.name, ...file.path]));
      final f = await diskfile.exists()
          ? _files[file] ??= _File.openFile(diskfile)
          : null;
      final start = max(0, offset - file.offset);
      final end = min(file.length, offset + length - file.offset);

      if (f != null) {
        while (f.lock != null) {
          await f.lock?.future;
        }
        final lock = Completer();
        f.lock = lock;
        try {
          await f.file.setPosition(offset);
          piece.buffer.setAll(setOffset, await f.file.read(end - start));
        } finally {
          f.lock = null;
          lock.complete();
        }
      }
      setOffset += end - start;
      if (setOffset == length) break;
    }
    return piece;
  }

  @override
  void writePiece(MetaData info, Piece piece) async {
    _bitfield[piece.index] = true;

    final offset = info.pieceLength * piece.index;
    final length = info.pieceSize(piece.index);
    var setOffset = 0;
    for (var file in info.files) {
      if (file.offset + file.length <= offset) continue;
      final diskfile = File(joinAll([dir, info.name, ...file.path]));
      final f = _files[file] ??= _File.openFile(diskfile);
      final start = max(0, offset - file.offset);
      final end = min(file.length, offset + length - file.offset);

      while (f.lock != null) {
        await f.lock?.future;
      }
      final lock = Completer();
      f.lock = lock;
      try {
        await f.file.setPosition(start);
        await f.file
            .writeFrom(piece.buffer, setOffset, setOffset + end - start);
      } finally {
        f.lock = null;
        lock.complete();
      }
      setOffset += end - start;
      if (setOffset == length) break;
    }
  }

  @override
  void close(MetaData info) {
    for (var file in info.files) {
      _files.remove(file);
    }
  }
}
