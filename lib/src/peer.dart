import 'dart:async';
import 'dart:io';

import 'package:torrent/src/bep/bep0003.dart';
import 'package:torrent/src/bep/bep0009.dart';
import 'package:torrent/src/bep/bep0010.dart';

class Peer extends PeerBep0003 with PeerBep0010, PeerBep0009 {
  Peer(InternetAddress ip, int port) : super(ip, port);

  @override
  void onHandshaked() {
    task?.peers.add(this);
    super.onHandshaked();
  }

  @override
  Future close() {
    task?.peers.remove(this);
    return super.close();
  }
}
