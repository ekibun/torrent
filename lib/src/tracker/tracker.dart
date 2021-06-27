part of 'package:torrent/torrent.dart';

class _AnnounceResponse {
  final int? interval;
  final List<Peer> peers = [];

  _AnnounceResponse(this.interval);
}

abstract class Tracker {
  final Uri url;
  int _lastAnnounced = 0; // sec
  int _announceInterval = 300; // sec

  Tracker(this.url);

  static Tracker fromUrl(String url) {
    if (url.startsWith('http')) return _HttpTracker(url);
    throw 'Unsupported tracker url=$url';
  }

  @override
  bool operator ==(b) => b is Tracker && b.url == url;

  @override
  int get hashCode => url.hashCode;

  Future<_AnnounceResponse> announce(
    ByteString infoHash,
    ByteString peerId,
    int port,
    int uploaded,
    int downloaded,
    int left,
  );
}

mixin _TrackerManager on _TorrentTask {
  final _trackers = <Tracker>{};
  void addTrackers(List<String> trackers) {
    for (var tr in trackers) {
      try {
        _trackers.add(Tracker.fromUrl(tr));
      } catch (error, stack) {
        _emitError(error, stack);
      }
    }
  }

  @override
  void _onUpdate(int now) {
    super._onUpdate(now);
    _trackers.forEach((tracker) {
      if (tracker._announceInterval > 0 &&
          now ~/ 1000 - tracker._lastAnnounced > tracker._announceInterval) {
        tracker._lastAnnounced = now ~/ 1000;
        tracker
            .announce(
          infoHash,
          peerId,
          port,
          uploaded,
          downloaded,
          left,
        )
            .then((rsp) {
          tracker._announceInterval = rsp.interval ?? tracker._announceInterval;
          rsp.peers.forEach((peer) => _onPeer(peer));
        }, onError: _emitError);
      }
    });
  }
}
