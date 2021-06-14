import 'dart:async';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/peer.dart';
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

  void onPeer(PeerInfo peer) {
    if (peers.any((p) => p.ip == peer.ip && p.port == peer.port)) return;
    peer.handshake(this).catchError((_) {});
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
          if (!(peerInfos is List<PeerInfo>) || peerInfos.isEmpty) return;
          peerInfos.forEach((peerInfo) async {
            Peer? peer;
            try {
              peer = await peerInfo.handshake(this);
              if (completer.isCompleted) throw 'completed';
              if (peer.reserved.bytes[5] & 0x10 == 0) {
                throw '$peer not support bep-10';
              }
              final handshake = Bencode.decode(
                  await peer.sendPacket(20, [
                    0,
                    ...Bencode.encode({
                      'm': {
                        'ut_metadata': 1,
                      }
                    })
                  ]),
                  1);
              final metaDataSize = handshake['metadata_size'] ?? 0;
              final utMetaData = handshake['m']?['ut_metadata'] ?? 0;
              if (metaDataSize == 0 || utMetaData == 0) {
                throw '$peer has no metadata';
              }
              const metaDataPieceSize = PIECE_SIZE;
              final metaDataPieceLength =
                  (metaDataSize / metaDataPieceSize).ceil();
              final metaDataBuffer = Uint8List(metaDataSize);
              for (var pid = 0; pid < metaDataPieceLength; ++pid) {
                final piece = await peer.sendPacket(20, [
                  utMetaData,
                  ...ByteString(Bencode.encode({'msg_type': 0, 'piece': pid}))
                      .bytes,
                ]);
                if (completer.isCompleted) return;
                final scanner = BencodeScanner(piece)..pos = 1;
                scanner.next();
                metaDataBuffer.setAll(
                    pid * metaDataPieceSize, piece.sublist(scanner.pos));
              }
              if (Torrent.parseInfoHash(metaDataBuffer).string !=
                  infoHash.string) {
                throw 'infohash not matched';
              }
              _torrent = Torrent.parse({
                'info': Bencode.decode(metaDataBuffer),
              });
              completer.complete(_torrent);
            } catch (_) {
              await peer?.close();
            }
          });
        })()
            .catchError((_) {}))).whenComplete(() {
      if (!completer.isCompleted) completer.completeError('cannot get torrent');
    });
    return completer.future;
  }
}
