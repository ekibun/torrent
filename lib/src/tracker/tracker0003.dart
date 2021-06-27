part of 'package:torrent/torrent.dart';

class _HttpTracker extends Tracker {
  _HttpTracker(String url) : super(Uri.parse(url));

  @override
  Future<_AnnounceResponse> announce(
    ByteString infoHash,
    ByteString peerId,
    int port,
    int uploaded,
    int downloaded,
    int left,
  ) async {
    final req = await HttpClient().getUrl(url.replace(
      query: {
        'info_hash': percent.encode(infoHash.bytes),
        'peer_id': percent.encode(peerId.bytes),
        'port': port,
        'uploaded': uploaded,
        'downloaded': downloaded,
        'left': left,
        'compact': 1,
      }.entries.map((e) => '${e.key}=${e.value}').join('&'),
    ));

    final rsp = Bencode.decode(Uint8List.fromList(
        (await (await req.close()).toList()).expand((p) => p).toList()));
    if (rsp['failure reason'] != null) throw rsp['failure reason'];
    final ret = _AnnounceResponse(rsp['interval']);
    final peers = rsp['peers'];
    if (peers is ByteString && peers.length > 0) {
      // BEP 23
      ret.peers.addAll(List.generate(
          peers.length ~/ 6,
          (i) => Peer(
              InternetAddress.fromRawAddress(
                  Uint8List.fromList(peers.bytes.sublist(i * 6, i * 6 + 4))),
              ByteString(peers.bytes.sublist(i * 6 + 4, i * 6 + 6)).toInt())));
    } else if (peers is List) {
      // BEP 03
      ret.peers.addAll(peers.map((peer) => Peer(
            InternetAddress.tryParse((peer['ip'] as ByteString).utf8)!,
            peer['port'],
          )));
    }
    // BEP 07
    final peers6 = rsp['peers6'];
    if (peers6 is ByteString && peers6.length > 0) {
      ret.peers.addAll(List.generate(
          peers6.length ~/ 18,
          (i) => Peer(
              InternetAddress.fromRawAddress(Uint8List.fromList(
                  peers6.bytes.sublist(i * 18, i * 18 + 16))),
              ByteString(peers6.bytes.sublist(i * 18 + 16, i * 18 + 18))
                  .toInt())));
    }
    return ret;
  }
}
