import 'package:torrent/src/magnet.dart';
import 'package:torrent/torrent.dart';

void main() async {
  final peerId = ByteString.str('nezumi test peer id!');
  final magnet = Magnet.parse(
      'magnet:?xt=urn:btih:H2THHKNRKJ4JQLI34DRJQEMHBQXCH3CV&dn=&tr=http%3A%2F%2F104.238.198.186%3A8000%2Fannounce&tr=udp%3A%2F%2F104.238.198.186%3A8000%2Fannounce&tr=http%3A%2F%2Ftracker.openbittorrent.com%3A80%2Fannounce&tr=udp%3A%2F%2Ftracker3.itzmx.com%3A6961%2Fannounce&tr=http%3A%2F%2Ftracker4.itzmx.com%3A2710%2Fannounce&tr=http%3A%2F%2Ftracker.publicbt.com%3A80%2Fannounce&tr=http%3A%2F%2Ftracker.prq.to%2Fannounce&tr=http%3A%2F%2Fopen.acgtracker.com%3A1096%2Fannounce&tr=https%3A%2F%2Ft-115.rhcloud.com%2Fonly_for_ylbud&tr=http%3A%2F%2Ftracker1.itzmx.com%3A8080%2Fannounce&tr=http%3A%2F%2Ftracker2.itzmx.com%3A6961%2Fannounce&tr=udp%3A%2F%2Ftracker1.itzmx.com%3A8080%2Fannounce&tr=udp%3A%2F%2Ftracker2.itzmx.com%3A6961%2Fannounce&tr=udp%3A%2F%2Ftracker3.itzmx.com%3A6961%2Fannounce&tr=udp%3A%2F%2Ftracker4.itzmx.com%3A2710%2Fannounce&tr=http%3A%2F%2Ftr.bangumi.moe%3A6969%2Fannounce');
  final torrent = await magnet.getTorrent(peerId);
  print(torrent);
  // final data = await File('test/test.torrent').readAsBytes();
  // final torrent = Torrent.parse(Bencode.decode(data));
  // final peerId = ByteString.str('nezumi test peer id!');
  // torrent.trackers.forEach((tracker) async {
  //   try {
  //     final rsp = await tracker.announce(torrent, peerId);
  //     final peerData = rsp['peers'];
  //     if (!(peerData is ByteString) || peerData.length == 0) return;
      // final peers = List.generate(
      //     peerData.length ~/ 6,
      //     (i) => Peer(
      //         InternetAddress.fromRawAddress(
      //             Uint8List.fromList(peerData.bytes.sublist(i * 6, i * 6 + 4))),
      //         ByteString(peerData.bytes.sublist(i * 6 + 4, i * 6 + 6))
      //             .toInt()));
  //     print('tracker:${tracker.url}');
  //     print(peers);
  //     peers.forEach((peer) async {
  //       try {
  //         final reserve = await peer.handshake(torrent.infoHash, peerId);
  //         if (reserve.bytes[5] & 0x10 != 0) {
  //           final newTorrent = Torrent.parse({
  //             'info': await peer.getMetaData(),
  //           });
  //           print(newTorrent);
  //         }
  //       } catch (e, stack) {
  //         if (!(e is SocketException)) print('$e\n$stack');
  //       }
  //     });
  //   } catch (e) {
  //     // print(e);
  //   }
  // });
  // final magnet = Uri.parse('magnet:?xt=urn:btih:a02aba6807df621a1c0a3f319d9521cd413196c4');
  // final kprc = Krpc();
  // kprc.info_hashs.add(ByteString.hex(magnet.queryParameters['xt']!.substring(9).toLowerCase()));
  // await kprc.bootstrap();
  // await Krpc().bootstrap();
  // final a = ByteString.int(0, 2);
  // final b = ByteString.int(4, 2);
  // print('$a-$b=${KNode(a, InternetAddress.anyIPv4, 0).distanceTo(b)}');
}
