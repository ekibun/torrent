import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/peer.dart';
import 'package:torrent/src/torrent.dart';
import 'package:torrent/src/tracker.dart';

class Magnet {
  final ByteString infoHash;
  String name;
  final TorrentTask task;
  Magnet(this.infoHash, this.name, this.task);

  static Magnet parse(String uri) {
    final magnet = Uri.parse(uri);
    final infoHashStr = magnet.queryParameters['xt']!.substring(9);
    final infoHash = infoHashStr.length == 40
        ? ByteString.hex(infoHashStr)
        : ByteString(base32.decode(infoHashStr));
    return Magnet(
      infoHash,
      magnet.queryParameters['dn'] ?? infoHashStr,
      TorrentTask()
        ..trackers.addAll((magnet.queryParametersAll['tr'] ?? [])
            .map((announce) => Tracker(announce))),
    );
  }

  Future<Torrent> getTorrent(ByteString peerId) {
    final completer = Completer<Torrent>();
    task.trackers.map((tracker) async {
      try {
        final announce = await tracker.announce(infoHash, peerId);
        if (completer.isCompleted) return;
        final peerData = announce['peers'];
        if (!(peerData is ByteString) || peerData.length == 0) return;
        final peerInfos = List.generate(
            peerData.length ~/ 6,
            (i) => PeerInfo(
                InternetAddress.fromRawAddress(Uint8List.fromList(
                    peerData.bytes.sublist(i * 6, i * 6 + 4))),
                ByteString(peerData.bytes.sublist(i * 6 + 4, i * 6 + 6))
                    .toInt()));
        print('$tracker return ${peerInfos.length} peers');
        peerInfos.forEach((peerInfo) async {
          Peer? peer;
          try {
            peer = await peerInfo.handshake(infoHash, peerId);
            if (completer.isCompleted) throw 'completed';
            peer.onClose = () => task.peers.remove(peer);
            task.peers.add(peer);
            print('$peer connected');
            if (peer.reserved.bytes[5] & 0x10 == 0) {
              throw '$peer not support bep-10';
            }
            final handshake = Bencode.decode(
                await peer.sendPacket(20, [
                  0,
                  ...Bencode.encode({
                    'm': {
                      'ut_metadata': 0,
                    }
                  })
                ]),
                1);
            final metaDataSize = handshake['metadata_size'] ?? 0;
            final utMetaData = handshake['m']?['ut_metadata'] ?? 0;
            if (metaDataSize == 0 || utMetaData == 0) {
              throw '$peer has no metadata';
            }
            const metaDataPieceSize = 16 * 1024;
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
            completer.complete(Torrent.parse({
              'info': Bencode.decode(metaDataBuffer),
            }, task: task));
          } catch (e) {
            await peer?.close();
            task.peers.remove(peer);
            if (!(e is SocketException)) print(e);
          }
        });
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });

    return completer.future;
  }
}
