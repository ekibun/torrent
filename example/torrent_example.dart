import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/peer.dart';
import 'package:torrent/src/torrent.dart';
import 'package:torrent/torrent.dart';

void main() async {
  final data = await File('test/test.torrent').readAsBytes();
  final torrent = Torrent.parse(Bencode.decode(data));
  final peerId = ByteString.str('nezumi test peer id!');
  torrent.trackers.forEach((tracker) async {
    try {
      final rsp = await tracker.announce(torrent, peerId);
      final peerData = rsp['peers'];
      if (!(peerData is ByteString) || peerData.length == 0) return;
      final peers = List.generate(
          peerData.length ~/ 6,
          (i) => Peer(
              InternetAddress.fromRawAddress(
                  Uint8List.fromList(peerData.bytes.sublist(i * 6, i * 6 + 4))),
              ByteString(peerData.bytes.sublist(i * 6 + 4, i * 6 + 6))
                  .toInt()));
      print('tracker:${tracker.url}');
      print(peers);
      peers.forEach((peer) async {
        try {
          final reserve = await peer.handshake(torrent.infoHash, peerId);
          if (reserve.bytes[5] & 0x10 != 0) {
            final newTorrent = Torrent.parse({
              'info': await peer.getMetaData(),
            });
            print(newTorrent);
          }
        } catch (e, stack) {
          if (!(e is SocketException)) print('$e\n$stack');
        }
      });
    } catch (e) {
      // print(e);
    }
  });
  // final magnet = Uri.parse('magnet:?xt=urn:btih:a02aba6807df621a1c0a3f319d9521cd413196c4');
  // final kprc = Krpc();
  // kprc.info_hashs.add(ByteString.hex(magnet.queryParameters['xt']!.substring(9).toLowerCase()));
  // await kprc.bootstrap();
  // await Krpc().bootstrap();
  // final a = ByteString.int(0, 2);
  // final b = ByteString.int(4, 2);
  // print('$a-$b=${KNode(a, InternetAddress.anyIPv4, 0).distanceTo(b)}');
}
