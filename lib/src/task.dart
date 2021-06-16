import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bep/bep0003.dart';
import 'package:torrent/src/peer.dart';
import 'package:torrent/src/piece.dart';
import 'package:torrent/src/socket.dart';
import 'package:torrent/src/torrent.dart';
import 'package:torrent/src/tracker.dart';
import 'package:crypto/crypto.dart' show sha1;

class _Request {
  final int index;
  final int offset;
  final int length;
  int time = 0;
  _Request(this.index, this.offset, this.length);

  @override
  bool operator ==(Object? b) =>
      b is _Request && b.index == index && b.offset == offset;

  @override
  int get hashCode => index * 100 + offset;
}

class TorrentTask {
  final ByteString infoHash;
  String? _name;
  final ByteString peerId;
  final List<Tracker> trackers = [];
  final List<Peer> peers = [];
  Torrent? _torrent;
  PieceStorage storage = LruPieceStorage();
  Timer? _updateRequestTimer;

  int blockSize = 2 << 14;

  int get port => 6881;
  int get uploaded => 0;
  int get downloaded => 0;
  int get left => 0;

  String get name =>
      _name ?? _torrent?.files.first.path[0] ?? infoHash.toString();

  TorrentTask._(this.infoHash, [ByteString? peerId])
      : peerId = peerId ?? ByteString.rand(20);

  void onPiece(PeerBep0003 peer, int index, int offset, Uint8List data) {
    _requesting
        .removeWhere((req) => req.index == index && req.offset == offset);
    var inPending = false;
    _blockPending.removeWhere((req, p) {
      if (req.index == index && req.offset == offset) {
        if (p != peer) {
          p.sendCancel(req.index, req.offset, req.length);
        } else {
          inPending = true;
        }
        return true;
      }
      return false;
    });
    if (!inPending) return;
    final blockIndex = offset ~/ BLOCK_SIZE;
    if (blockIndex * BLOCK_SIZE != offset || data.length > BLOCK_SIZE) {
      print('onPiece[$index](offset=$offset, len=${data.length})');
    } else {
      storage.writeBlock(index, blockIndex, data).then((piece) {
        final torrent = _torrent;
        if (torrent == null) return;
        final blockInPieces = torrent.blocksInPiece(index);
        print(piece.blocks
            .toString()
            .padRight(blockInPieces, '0')
            .substring(0, blockInPieces));
        if (piece.blocks.isFullfilled(blockInPieces)) {
          final hash =
              ByteString(sha1.convert(piece.buffer).bytes).toString() ==
                  ByteString(torrent.pieces[index]).toString();
          print('check piece $index: $hash');
        }
      });
    }
  }

  final _blockPending = <_Request, Peer>{};
  final _requesting = Queue<_Request>();

  void stop() {
    pause();
    List.from(peers).forEach((peer) => peer.close());
  }

  void pause() {
    _updateRequestTimer?.cancel();
    trackers.forEach((tracker) => tracker.stop());
    _blockPending.forEach((key, value) {
      value.sendCancel(key.index, key.offset, key.length);
    });
    _blockPending.clear();
  }

  void start() {
    trackers.forEach((tracker) => tracker.start());
    _updateRequestTimer = Timer.periodic(Duration(milliseconds: 500), (_) {
      _blockPending.removeWhere((req, peer) {
        if (req.time > DateTime.now().millisecondsSinceEpoch - 5 * 1000) {
          return false;
        }
        _requesting.addFirst(req);
        return true;
      });
      while (_requesting.isNotEmpty) {
        final req = _requesting.first;
        for (var peer in peers) {
          final havePiece = peer.bitfield[req.index];
          if (!havePiece) continue;
          if (peer.isChoking) {
            peer.interested();
            continue;
          }
          if (_blockPending.values.where((p) => p == peer).length > 3) continue;
          peer.request(req.index, req.offset, req.length);
          _requesting.removeFirst();
          req.time = DateTime.now().millisecondsSinceEpoch;
          _blockPending[req] = peer;
          break;
        }
        if (_requesting.isNotEmpty && _requesting.first == req) break;
      }
    });
  }

  void requestPiece(int index) {
    final torrent = _torrent!;
    final pieceLength =
        min(torrent.pieceLength, torrent.length - index * torrent.pieceLength);
    final blocks = (pieceLength / BLOCK_SIZE).ceil();
    for (var b = 0; b < blocks; ++b) {
      final offset = b * BLOCK_SIZE;
      final length = min(BLOCK_SIZE, pieceLength - b * BLOCK_SIZE);
      assert(length > 0);
      final req = _Request(index, offset, length);
      if (_requesting.contains(req)) continue;
      _requesting.add(req);
    }
  }

  void onPeer(Peer peer) {
    if (peers.any((p) => p.ip == peer.ip && p.port == peer.port)) return;
    peer.handshake(TcpPeerSocket.connect, this).then((_) {}).catchError((_) {});
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
              _torrent = Torrent.parse({
                'info': Bencode.decode(await peer.getMetadata()),
              });
              completer.complete(_torrent);
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
