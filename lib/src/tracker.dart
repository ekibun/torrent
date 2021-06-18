part of 'package:torrent/torrent.dart';

class _AnnounceResponse {
  final int interval;
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

class _HttpTracker extends Tracker {
  _HttpTracker(String url) : super(Uri.parse(url));

  @override
  Future<_AnnounceResponse> announce(
    ByteString infoHash,
    ByteString peerId,
    int port,
    int uploaded,
    int downloaded,
    int left,
  ) async {
    final req = await HttpClient().getUrl(url.replace(
      query: {
        'info_hash': percent.encode(infoHash.bytes),
        'peer_id': percent.encode(peerId.bytes),
        'port': port,
        'uploaded': uploaded,
        'downloaded': downloaded,
        'left': left,
        'compact': 1,
      }.entries.map((e) => '${e.key}=${e.value}').join('&'),
    ));

    final rsp = Bencode.decode(Uint8List.fromList(
        (await (await req.close()).toList()).expand((p) => p).toList()));
    if (rsp['failure reason'] != null) throw rsp['failure reason'];
    _announceInterval = rsp['interval'];
    final ret = _AnnounceResponse(_announceInterval);
    final peers = rsp['peers'];
    if (peers is ByteString && peers.length > 0) {
      // BEP 23
      ret.peers.addAll(List.generate(
          peers.length ~/ 6,
          (i) => Peer(
              InternetAddress.fromRawAddress(
                  Uint8List.fromList(peers.bytes.sublist(i * 6, i * 6 + 4))),
              ByteString(peers.bytes.sublist(i * 6 + 4, i * 6 + 6)).toInt())));
    } else if (peers is List) {
      // BEP 03
      ret.peers.addAll(peers.map((peer) => Peer(
            InternetAddress.tryParse((peer['ip'] as ByteString).utf8)!,
            peer['port'],
          )));
    }
    return ret;
  }
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
            .then((rsp) => rsp.peers.forEach((peer) => _onPeer(peer)))
            .catchError(_emitError);
      }
    });
  }
}
