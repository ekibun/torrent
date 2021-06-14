import 'package:dio/dio.dart';
import 'package:torrent/src/bencode.dart';
import 'package:convert/convert.dart';

class Tracker {
  final String url;
  Tracker(this.url);

  Future announce(
    ByteString infoHash,
    ByteString peerId, {
    int port = 6881,
    int uploaded = 0,
    int downloaded = 0,
    int left = 0,
    int compact = 1,
  }) async {
    final query = {
      'info_hash': percent.encode(infoHash.bytes),
      'peer_id': percent.encode(peerId.bytes),
      'port': port,
      'uploaded': uploaded,
      'downloaded': downloaded,
      'left': left,
      'compact': compact,
    }.entries.map((e) => '${e.key}=${e.value}').join('&');
    return Bencode.decode((await Dio().get('$url?$query',
            options: Options(responseType: ResponseType.bytes)))
        .data);
  }

  @override
  String toString() => 'Tracker($url)';
}
