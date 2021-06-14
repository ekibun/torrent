import 'package:dio/dio.dart';
import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/torrent.dart';
import 'package:convert/convert.dart';

class Tracker {
  final String url;
  Tracker(this.url);

  Future announce(Torrent torrent, ByteString peerId) async {
    final query = {
      'info_hash': percent.encode(torrent.infoHash.bytes),
      'peer_id': percent.encode(peerId.bytes),
      'port': 6881,
      'uploaded': 0,
      'downloaded': 0,
      'left': 0,
      'compact': 1,
    }.entries.map((e) => '${e.key}=${e.value}').join('&');
    return Bencode.decode((await Dio().get('$url?$query',
            options: Options(responseType: ResponseType.bytes)))
        .data);
  }
}
