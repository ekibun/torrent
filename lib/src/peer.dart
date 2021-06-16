import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent/src/bep/bep0003.dart';
import 'package:torrent/src/bep/bep0006.dart';
import 'package:torrent/src/bep/bep0009.dart';
import 'package:torrent/src/bep/bep0010.dart';
import 'package:torrent/src/bep/bep0054.dart';

class Peer extends PeerBep0003
    with PeerBep0006, PeerBep0010, PeerBep0009, PeerBep0054 {
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
