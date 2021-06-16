import 'dart:typed_data';

import 'package:torrent/src/bitfield.dart';

import 'bep/bep0003.dart';

class Piece {
  Uint8List buffer = Uint8List(0);
  final Bitfield blocks = Bitfield();
}

abstract class PieceStorage {
  Future<Piece> getPiece(int index, int pieceLength);

  Future<Piece> writeBlock(int index, int block, Uint8List data);
}

class LruPieceStorage extends PieceStorage {
  final int size;

  LruPieceStorage({
    this.size = 2 << 24, // 16 MB
  });

  final _pieces = <int, Piece>{};

  @override
  Future<Piece> getPiece(int index, int pieceLength) async {
    final ret = _pieces.remove(index) ?? Piece();
    if (_pieces.length > size / pieceLength) {
      _pieces.remove(_pieces.entries.first.key);
    }
    _pieces[index] = ret;
    return ret;
  }

  @override
  Future<Piece> writeBlock(int index, int block, Uint8List data) async {
    final pieceLength = BLOCK_SIZE * block + data.length;
    var piece = _pieces.remove(index) ?? Piece();
    if (piece.buffer.length < pieceLength) {
      piece.buffer = Uint8List(pieceLength)..setAll(0, piece.buffer);
    }
    _pieces[index] = piece;
    piece.buffer.setAll(block * BLOCK_SIZE, data);
    piece.blocks[block] = true;
    return piece;
  }
}
