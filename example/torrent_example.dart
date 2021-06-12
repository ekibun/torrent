import 'dart:io';

import 'package:torrent/src/dht.dart';
import 'package:torrent/torrent.dart';

void main() async {
  final magnet = Uri.parse('magnet:?xt=urn:btih:c9ec3c5df0d9a7f30d7ad679056b360547d93939');
  final kprc = Krpc();
  print(magnet.queryParameters['xt']);
  kprc.info_hashs.add(ByteString.hex(magnet.queryParameters['xt']!.substring(9).toLowerCase()));
  await kprc.bootstrap();
  // await Krpc().bootstrap();
  // final a = ByteString.int(0, 2);
  // final b = ByteString.int(4, 2);
  // print('$a-$b=${KNode(a, InternetAddress.anyIPv4, 0).distanceTo(b)}');
}
