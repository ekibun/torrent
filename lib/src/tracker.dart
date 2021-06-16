import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:torrent/src/bencode.dart';
import 'package:convert/convert.dart';
import 'package:torrent/src/peer.dart';
import 'package:torrent/src/task.dart';

class Tracker {
  final String url;
  final TorrentTask _task;
  Timer? _timer;
  Tracker(this.url, this._task);

  Future announce() async {
    final query = {
      'info_hash': percent.encode(_task.infoHash.bytes),
      'peer_id': percent.encode(_task.peerId.bytes),
      'port': _task.port,
      'uploaded': _task.uploaded,
      'downloaded': _task.downloaded,
      'left': _task.left,
      'compact': 1,
    }.entries.map((e) => '${e.key}=${e.value}').join('&');
    final rsp = Bencode.decode((await Dio().get('$url?$query',
            options: Options(responseType: ResponseType.bytes)))
        .data);
    final peers = rsp['peers'];
    if (peers is ByteString && peers.length > 0) {
      rsp['peers'] = List<Peer>.generate(
          peers.length ~/ 6,
          (i) => Peer(
              InternetAddress.fromRawAddress(
                  Uint8List.fromList(peers.bytes.sublist(i * 6, i * 6 + 4))),
              ByteString(peers.bytes.sublist(i * 6 + 4, i * 6 + 6)).toInt()));
    } else {
      rsp['peers'] = [];
    }
    return rsp;
  }

  Future _recursive() async {
    final resp = await announce();
    final peers = resp['peers'];
    if (peers is List<Peer>) {
      peers.forEach((peer) => _task.onPeer(peer));
    }
  }

  void start() {
    if (_timer != null) return;
    announce().then((data) {
      final int interval = data['min interval'] ?? data['interval'] ?? 300;
      _timer = Timer.periodic(Duration(seconds: interval),
          (_) => _recursive().catchError((_) => {}));
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  String toString() => 'Tracker($url)';
}
