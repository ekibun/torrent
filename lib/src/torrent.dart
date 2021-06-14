import 'dart:typed_data';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/peer.dart';
import 'package:torrent/src/tracker.dart';
import 'package:crypto/crypto.dart' show sha1;

class TorrentFile {
  List<String> path;
  int length;
  int offset;
  TorrentFile(
    this.path,
    this.length, [
    this.offset = 0,
  ]);
}

class TorrentTask {
  final ByteString peerId;
  final List<Tracker> trackers = [];
  final List<Peer> peers = [];

  TorrentTask([ByteString? peerId]) : peerId = peerId ?? ByteString.rand(20);
}

class Torrent {
  final ByteString infoHash;
  final TorrentTask task;
  final List<TorrentFile> files;
  final int? creationDate;
  final String? createdBy;
  final int pieceLength;
  final Uint8List pieces;

  Torrent._(
    this.infoHash,
    this.task,
    this.files,
    this.pieceLength,
    this.pieces, [
    this.creationDate,
    this.createdBy,
  ]);

  static Torrent parse(Map data, {TorrentTask? task}) {
    final trackers = <Tracker>[];
    final announceList = data['announce-list'];
    final announce = data['announce'];
    if (announceList is List) {
      for (var announces in announceList) {
        trackers.addAll(List<Tracker>.from(
            announces.map((announce) => Tracker(announce.string))));
      }
    } else if (announce is ByteString) {
      trackers.add(Tracker(announce.string));
    }
    final torrentFiles = <TorrentFile>[];
    final files = data['info']['files'];
    final name = data['info']['name'];
    if (files is List) {
      var offset = 0;
      torrentFiles.addAll(files.map((file) {
        int length = file['length'];
        offset += length;
        return TorrentFile(
            List<String>.from([name, ...file['path']].map((b) => b.string)),
            length,
            offset - length);
      }));
    } else {
      torrentFiles.add(TorrentFile([name.string], data['info']['length']));
    }
    return Torrent._(
      parseInfoHash(Bencode.encode(data['info'])),
      task ?? (TorrentTask()..trackers.addAll(trackers)),
      torrentFiles,
      data['info']['piece length'],
      data['info']['pieces'].bytes,
      data['creation date'],
      data['created by']?.string,
    );
  }

  static ByteString parseInfoHash(Uint8List info) =>
      ByteString(sha1.convert(info).bytes);
}
