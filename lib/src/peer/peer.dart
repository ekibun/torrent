part of 'package:torrent/torrent.dart';

const BITTORRENT_PROTOCOL = 'BitTorrent protocol';

class Peer extends _Peer0003 with _Peer0010, _Peer0009 {
  Peer(InternetAddress ip, int port) : super(ip, port);

  @override
  String toString() => 'Peer(v=$client addr=${ip.address}:$port)';

  int _downloaded = 0;
  int _lastDownloaded = 0;
  int _downloadSpeed = 0; // byte/s
  int get downloadSpeed => _downloadSpeed;

  @override
  void _onPiece(int index, int offset, Uint8List data) {
    _downloaded += data.length;
    super._onPiece(index, offset, data);
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

  Future<bool> _onPeer(Peer peer) {
    if (_peers.add(peer)) {
      _stream.add(PeerAdded(peer));
      final ret = peer._handshake(this);
      ret
          .then((socket) {
            _stream.add(PeerConnected(peer));
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

  @override
  void _onUpdate(int now) {
    super._onUpdate(now);
    if (_lastPeerTime == 0) {
      _lastPeerTime = now;
      return;
    }
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
  }

  void _onPiece(int index, int offset, Uint8List data) {}
}
