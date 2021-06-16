import 'dart:async';
import 'dart:io';

import 'package:base32/base32.dart';
import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/peer.dart';
import 'package:torrent/src/socket.dart';
import 'package:torrent/src/torrent.dart';
import 'package:torrent/src/tracker.dart';

class TorrentTask {
  final ByteString infoHash;
  String? _name;
  final ByteString peerId;
  final List<Tracker> trackers = [];
  final List<Peer> peers = [];
  Torrent? _torrent;

  int get port => 6881;
  int get uploaded => 0;
  int get downloaded => 0;
  int get left => 0;

  String get name =>
      _name ?? _torrent?.files.first.path[0] ?? infoHash.toString();

  TorrentTask._(this.infoHash, [ByteString? peerId])
      : peerId = peerId ?? ByteString.rand(20);

  void onPiece(int index, int offset, List<int> data) {
    print('onPiece[$index](offset=$offset, len=${data.length})');
  }

  void stop() {
    trackers.forEach((tracker) => tracker.stop());
    List.from(peers).forEach((peer) => peer.close());
  }

  void start() {
    trackers.forEach((tracker) => tracker.start());
  }

  void onPeer(Peer peer) {
    if (peers.any((p) => p.ip == peer.ip && p.port == peer.port)) return;
    peer.handshake(TcpPeerSocket.connect, this).catchError((_) {});
  }

  static TorrentTask fromMagnet(String uri) {
    final magnet = Uri.parse(uri);
    final infoHashStr = magnet.queryParameters['xt']!.substring(9);
    final infoHash = infoHashStr.length == 40
        ? ByteString.hex(infoHashStr)
        : ByteString(base32.decode(infoHashStr));
    final task = TorrentTask._(infoHash);
    task._name = magnet.queryParameters['dn'];
    task.trackers.addAll(
        (magnet.queryParametersAll['tr'] ?? []).map((e) => Tracker(e, task)));
    return task;
  }

  static TorrentTask fromTorrent(Torrent torrent) {
    final task = TorrentTask._(torrent.infoHash);
    task._torrent = torrent;
    task.trackers.addAll(torrent.announces.map((url) => Tracker(url, task)));
    return task;
  }

  Future<Torrent> getTorrent(ByteString peerId) {
    if (_torrent != null) return Future.value(_torrent);
    final completer = Completer<Torrent>();
    Future.wait(trackers.map<Future<dynamic>>((tracker) => (() async {
          final announce = await tracker.announce();
          if (completer.isCompleted) return;
          final peerInfos = announce['peers'];
          if (!(peerInfos is List<Peer>) || peerInfos.isEmpty) return;
          peerInfos.forEach((peer) async {
            try {
              await peer.handshake(TcpPeerSocket.connect, this);
              completer.complete(Torrent.parse({
                'info': Bencode.decode(await peer.getMetadata()),
              }));
            } catch (_) {
              await peer.close();
            }
          });
        })()
            .catchError((_) {}))).whenComplete(() {
      if (!completer.isCompleted) {
        completer.completeError(SocketException('cannot get torrent'));
      }
    });
    return completer.future;
  }
}
