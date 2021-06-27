part of 'package:torrent/torrent.dart';

const BITTORRENT_PROTOCOL = 'BitTorrent protocol';

class Peer extends _Peer0003 with _Peer0006, _Peer0010, _Peer0009 {
  Peer(InternetAddress ip, int port) : super(ip, port);

  @override
  String toString() => 'Peer(v=$client addr=${ip.address}:$port)';

  int _downloaded = 0;
  int _lastDownloaded = 0;
  int _downloadSpeed = 0; // byte/s
  int _downloadPieceCount = 0;
  int get downloadSpeed => _downloadSpeed;

  @override
  void _onMessage(_PeerManager task, int op, Uint8List data) {
    super._onMessage(task, op, data);
    if (op == _Peer0003.OP_PIECE) _downloaded += data.length - 8;
  }

  @override
  bool operator ==(b) =>
      b is Peer && b.ip.address == ip.address && b.port == port;

  @override
  int get hashCode => port;
}

class PeerAdded extends TorrentMessage {
  final Peer peer;
  PeerAdded(this.peer);
}

class PeerConnected extends TorrentMessage {
  final Peer peer;
  PeerConnected(this.peer);
}

class PeerDisconnected extends TorrentMessage {
  final Peer peer;
  PeerDisconnected(this.peer);
}

mixin _PeerManager on _BaseTorrent {
  final _peers = <Peer>{};

  TorrentStorage? storage;

  Future<bool> _onPeer(Peer peer) {
    if (_peers.add(peer)) {
      _stream.add(PeerAdded(peer));
      final ret = peer._handshake(this);
      ret
          .then((socket) {
            _stream.add(PeerConnected(peer));
            _onPeerConnected(peer);
            return socket.done;
          })
          .catchError(_emitError)
          .whenComplete(() {
            _stream.add(PeerDisconnected(peer));
            _peers.remove(peer);
          });
      return ret.then((value) => true, onError: (error, stack) {
        _emitError(error, stack);
        return false;
      });
    }
    return Future.value(false);
  }

  int _lastPeerTime = 0;
  int _lastT = 0;
  int _lastNT = 0;
  int _lastMT = 0;

  static const _CHOCKING_TIME = 10000;

  @override
  void _onUpdate(int now) {
    super._onUpdate(now);
    if (_lastPeerTime == 0 || now - _lastPeerTime > 5000) {
      for (var peer in _peers) {
        peer.keepalive();
        peer._downloadSpeed = (peer._downloaded - peer._lastDownloaded) *
            1000 ~/
            (now - _lastPeerTime);
        peer._lastDownloaded = peer._downloaded;
      }
      _lastPeerTime = now;
    }
    if (storage == null) return;
    if (_lastT == 0 || now - _lastT > _CHOCKING_TIME) {
      // Choking Algorithm
      final peers = _peers
          .where((peer) => peer.amChoking && peer.isInterested)
          .toList()
            ..sort((a, b) => b.downloadSpeed - a.downloadSpeed);
      for (var peer in peers.take(7)) {
        if (peer.amChoking && peer.isInterested) {
          peer.unchoke();
        }
      }
      _lastT = now;
    }
    if (_lastNT == 0 || now - _lastNT > 3 * _CHOCKING_TIME) {
      // Optimistic Unchoking
      final peers =
          _peers.where((peer) => peer.amChoking && peer.isConnected).toList();
      if (peers.isNotEmpty) {
        peers[Random().nextInt(peers.length)].unchoke();
      }
      _lastNT = now;
    }
    if (_lastMT == 0 || now - _lastMT > 6 * _CHOCKING_TIME) {
      // Anti-snubbing
      for (var peer in _peers) {
        final count = peer._downloadPieceCount;
        peer._downloadPieceCount = 0;
        if (!peer.amChoking && count == 0) peer.choke();
      }
      _lastMT = now;
    }
  }

  void _onPiece(int index, int offset, Uint8List data) {}

  void _onPeerConnected(Peer peer) {
    final s = storage;
    final metadata = _metadata;
    if (s == null || metadata == null) {
    } else if (s.bitfield.bytes.isEmpty) {
      if (peer.isSupportedFastExtension) {
        peer.sendHaveNone();
      }
    } else {
      peer.sendBitfield(s.bitfield.._grow(metadata.pieces.length));
    }
  }

  final _peerRequestingPieces = <int, Future<Piece>>{};

  void _onRequest(Completer<Piece> cb, int index, int offset, int length) {
    if (cb.isCompleted) return;
    final s = storage;
    final metadata = _metadata;
    if (s == null || metadata == null) return cb.completeError('no data');
    final getPiece =
        _peerRequestingPieces[index] ??= s.getPiece(metadata, index)
          ..then((value) {
            _peerRequestingPieces.remove(index);
          });
    getPiece.then((piece) {
      if (cb.isCompleted) return;
      cb.complete(piece);
    }, onError: _emitError);
  }
}
