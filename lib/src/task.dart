import 'dart:async';
import 'dart:io';
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

  String get name =>
      _name ?? _torrent?.files.first.path[0] ?? infoHash.toString();

  TorrentTask._(this.infoHash, [ByteString? peerId])
      : peerId = peerId ?? ByteString.rand(20);

  void onPiece(int index, int offset, List<int> data) {
    print('onPiece[$index](offset=$offset, len=${data.length})');
  }

  static TorrentTask fromMagnet(String uri) {
    final magnet = Uri.parse(uri);
    final infoHashStr = magnet.queryParameters['xt']!.substring(9);
    final infoHash = infoHashStr.length == 40
        ? ByteString.hex(infoHashStr)
        : ByteString(base32.decode(infoHashStr));
    return TorrentTask._(
      infoHash,
    )
      .._name = magnet.queryParameters['dn']
      ..trackers.addAll(
          (magnet.queryParametersAll['tr'] ?? []).map((e) => Tracker(e)));
  }

  static TorrentTask fromTorrent(Torrent torrent) {
    return TorrentTask._(
      torrent.infoHash,
    ).._torrent = torrent;
  }

  Future<Torrent> getTorrent(ByteString peerId) {
    if (_torrent != null) return Future.value(_torrent);
    final completer = Completer<Torrent>();
    Future.wait(trackers.map<Future>((tracker) async {
      final announce = await tracker.announce(infoHash, peerId);
      if (completer.isCompleted) return;
      final peerData = announce['peers'];
      if (!(peerData is ByteString) || peerData.length == 0) return;
      final peerInfos = List.generate(
          peerData.length ~/ 6,
          (i) => PeerInfo(
              InternetAddress.fromRawAddress(
                  Uint8List.fromList(peerData.bytes.sublist(i * 6, i * 6 + 4))),
              ByteString(peerData.bytes.sublist(i * 6 + 4, i * 6 + 6))
                  .toInt()));
      print('$tracker return ${peerInfos.length} peers');
      peerInfos.forEach((peerInfo) async {
        Peer? peer;
        try {
          peer = await peerInfo.handshake(this);
          if (completer.isCompleted) throw 'completed';
          print('$peer connected');
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
          final metaDataPieceLength = (metaDataSize / metaDataPieceSize).ceil();
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
          if (Torrent.parseInfoHash(metaDataBuffer).string != infoHash.string) {
            throw 'infohash not matched';
          }
          _torrent = Torrent.parse({
            'info': Bencode.decode(metaDataBuffer),
          });
          completer.complete(_torrent);
        } catch (e) {
          await peer?.close();
        }
      });
    })).whenComplete(() {
      if (!completer.isCompleted) completer.completeError('cannot get torrent');
    });
    return completer.future;
  }
}
