import 'dart:async';
import 'dart:io';

import 'package:torrent/src/bencode.dart';
import 'package:torrent/src/bep/bep0003.dart';
import 'package:torrent/src/bep/bep0009.dart';
import 'package:torrent/src/bep/bep0010.dart';
import 'package:torrent/src/socket.dart';
import 'package:torrent/src/task.dart';

class PeerInfo extends BasePeerInfo<TcpPeerSocket, Peer> with PeerInfoBep0010 {
  PeerInfo(InternetAddress ip, int port) : super(ip, port);

  @override
  Future<TcpPeerSocket> connect() => TcpPeerSocket.connect(ip, port);

  @override
  Peer createPeer(TcpPeerSocket socket, ByteString reserved, ByteString id,
          TorrentTask task) =>
      Peer(task, id, reserved, socket);
}

class Peer extends BasePeer with PeerBep0010, PeerBep0009 {
  Peer(TorrentTask task, ByteString id, ByteString reserved, PeerSocket socket)
      : super(task, id, reserved, socket) {
    task.peers.add(this);
    if (isSupportedExtendMessage) extendHandshake();
  }

  @override
  Future close() {
    task.peers.remove(this);
    return super.close();
  }
}
