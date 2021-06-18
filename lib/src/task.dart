part of 'package:torrent/torrent.dart';

class Piece {
  final Uint8List buffer;
  final Bitfield blocks = Bitfield();

  final int index;
  Piece(this.index, int length) : buffer = Uint8List(length);

  @override
  String toString() => 'Piece[$index]';
}

class _BlockRequest {
  final int index;
  final int offset;
  final int length;
  final int time;

  _BlockRequest(this.index, this.offset, this.length)
      : time = DateTime.now().millisecondsSinceEpoch;

  @override
  String toString() => 'Request(index=$index, offset=$offset)';

  @override
  bool operator ==(b) =>
      b is _BlockRequest && b.index == index && b.offset == offset;

  static bool Function(_BlockRequest) comparator(int index, int offset) =>
      (p) => p.index == index && p.offset == offset;
}

class PieceChecked extends TorrentMessage {
  final Piece piece;

  PieceChecked(this.piece);
}

mixin _TorrentTask on _PeerManager {
  int port = 0;
  int uploaded = 0;
  int downloaded = 0;
  int left = 0;

  final _requestingBlocks = <_BlockRequest>{};
  final _pendingPieces = <Piece>{};
  final _requestingPieces = <int>{};

  void downloadPieces(int from, int to) {
    for (var i = from; i < to; ++i) {
      _requestingPieces.add(i);
    }
  }

  @override
  void _onPiece(int index, int offset, Uint8List data) {
    super._onPiece(index, offset, data);
    final comp = _BlockRequest.comparator(index, offset);
    _requestingBlocks.removeWhere(comp);
    for (var peer in _peers) {
      peer._pendingBlocks.removeWhere((req) {
        if (!comp(req)) return false;
        peer.sendCancel(req.index, req.offset, req.length);
        return true;
      });
    }
    final blockIndex = offset ~/ BLOCK_SIZE;
    if (blockIndex * BLOCK_SIZE != offset || data.length > BLOCK_SIZE) {
      throw ('Unsupported onPiece[$index](offset=$offset, len=${data.length})');
    } else {
      final piece = _pendingPieces.firstWhere((p) => p.index == index);
      piece.buffer.setAll(offset, data);
      piece.blocks[blockIndex] = true;
      print('$index - ${piece.blocks}');
      if (piece.blocks
          .isFullfilled((piece.buffer.length / BLOCK_SIZE).ceil())) {
        if (ByteString(sha1.convert(piece.buffer).bytes).toString() !=
            _metadata!.pieces[index].toString()) {
          throw 'hash not match';
        }
        _pendingPieces.remove(piece);
        _stream.add(PieceChecked(piece));
      }
    }
  }

  @override
  void _onUpdate(int now) {
    super._onUpdate(now);
    for (var peer in _peers) {
      if (!peer.isConnected) continue;
      peer._pendingBlocks.removeWhere((req) {
        if (now - req.time < 5000) return false;
        _requestingBlocks.add(req);
        return true;
      });
      if (_requestingBlocks.isEmpty) continue;
      final consumed = <_BlockRequest>[];
      for (var req in _requestingBlocks) {
        if (peer._pendingBlocks.length > 10 + peer.downloadSpeed / BLOCK_SIZE) {
          break;
        }
        final havePiece = peer.bitfield[req.index];
        if (!havePiece) continue;
        if (peer.isChoking) {
          peer.interested();
          continue;
        }
        consumed.add(req);
        peer.request(req.index, req.offset, req.length);
      }
      _requestingBlocks.removeAll(consumed);
    }
    final metadata = _metadata;
    if (metadata == null) return;
    while (_requestingBlocks.length < 100) {
      if (_requestingPieces.isEmpty) break;
      final index = _requestingPieces.first;
      _requestingPieces.remove(index);
      _pendingPieces.add(Piece(index, metadata.pieceSize(index)));
      final blocks = metadata.blocksInPiece(index);
      for (var b = 0; b < blocks; ++b) {
        final offset = b * BLOCK_SIZE;
        final length = metadata.blockSize(index, b);
        _requestingBlocks.add(_BlockRequest(index, offset, length));
      }
    }
  }
}
