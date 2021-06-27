part of 'package:torrent/torrent.dart';

const BLOCK_SIZE = 1 << 14;

class TorrentMessage {}

class TorrentError extends TorrentMessage {
  final error;
  final stack;
  TorrentError(this.error, this.stack);
}

class _BaseTorrent {
  final ByteString peerId;
  final ByteString infoHash;

  MetaData? _metadata;

  Timer? _updateTimer;
  void _onUpdate(int now) {}

  final _stream = StreamController<TorrentMessage>.broadcast();
  void _emitError(error, stack) {
    _stream.add(TorrentError(error, stack));
  }

  Stream<T> on<T extends TorrentMessage>() {
    return _stream.stream.where((m) => m is T).cast<T>();
  }

  _BaseTorrent(this.infoHash, this.peerId);

  bool get isRunning => _updateTimer?.isActive ?? false;

  void start() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(
      Duration(seconds: 1),
      (_) => _onUpdate(DateTime.now().millisecondsSinceEpoch),
    );
  }

  void pause() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  void stop() {
    pause();
  }
}

class Torrent extends _BaseTorrent
    with _PeerManager, _TorrentTask, _TrackerManager {
  Torrent._(ByteString infoHash, [ByteString? peerId])
      : super(infoHash, peerId ?? ByteString.rand(20));

  static Torrent fromTorrentData(Uint8List bytes, [ByteString? peerId]) {
    final data = Bencode.decode(bytes);
    final trackers = <String>[];
    final announceList = data['announce-list'];
    final announce = data['announce'];
    if (announceList is List) {
      // BEP 12
      for (var announces in announceList) {
        trackers.addAll(List.from(announces.map((announce) => announce.utf8)));
      }
    } else if (announce is ByteString) {
      trackers.add(announce.utf8);
    }
    final metadata = MetaData.fromMap(data['info']);
    return Torrent._(metadata.infoHash, peerId)
      .._metadata = metadata
      ..addTrackers(trackers);
  }

  static Torrent fromMagnet(String uri, [ByteString? peerId]) {
    final magnet = Uri.parse(uri);
    final infoHashStr = magnet.queryParameters['xt']!.substring(9);
    final infoHash = infoHashStr.length == 40
        ? ByteString.hex(infoHashStr)
        : ByteString(base32.decode(infoHashStr));
    return Torrent._(infoHash, peerId)
      ..addTrackers(magnet.queryParametersAll['tr'] ?? []);
  }

  Future<MetaData> getMetaData() {
    if (_metadata != null) return Future.value(_metadata);
    final completer = Completer<MetaData>();
    Future.wait(_trackers.map<Future<dynamic>>((tracker) async {
      try {
        final announce = await tracker.announce(
            infoHash, peerId, port, uploaded, downloaded, left);
        if (completer.isCompleted) return;
        announce.peers.forEach((peer) async {
          try {
            if (await _onPeer(peer) == false) return;
            final metadata = await peer.getMetadata(completer);
            if (MetaData.parseInfoHash(metadata).utf8 != infoHash.utf8) {
              throw 'infohash not matched';
            }
            _metadata = MetaData.fromMap(Bencode.decode(metadata));
            completer.complete(_metadata);
          } catch (error, stack) {
            _emitError(error, stack);
            await peer.close();
          }
        });
      } catch (error, stack) {
        _emitError(error, stack);
      }
    })).whenComplete(() {
      if (!completer.isCompleted) {
        completer.completeError(SocketException('cannot get metadata'));
      }
    });
    return completer.future;
  }
}
