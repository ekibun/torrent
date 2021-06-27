import 'package:torrent/bencode.dart';
import 'package:torrent/storage.dart';
import 'package:torrent/torrent.dart';

void main() async {
  final peerId = ByteString.str('nezumi test peer id!');
  final torrent = Torrent.fromMagnet(
    'magnet:?xt=urn:btih:DQIGG3BU3XCXQQN4QCFGPUXK6LDLI6CG&dn=&tr=http%3A%2F%2F104.238.198.186%3A8000%2Fannounce&tr=udp%3A%2F%2F104.238.198.186%3A8000%2Fannounce&tr=http%3A%2F%2Ftracker.openbittorrent.com%3A80%2Fannounce&tr=udp%3A%2F%2Ftracker3.itzmx.com%3A6961%2Fannounce&tr=http%3A%2F%2Ftracker4.itzmx.com%3A2710%2Fannounce&tr=http%3A%2F%2Ftracker.publicbt.com%3A80%2Fannounce&tr=http%3A%2F%2Ftracker.prq.to%2Fannounce&tr=http%3A%2F%2Fopen.acgtracker.com%3A1096%2Fannounce&tr=https%3A%2F%2Ft-115.rhcloud.com%2Fonly_for_ylbud&tr=http%3A%2F%2Ftracker1.itzmx.com%3A8080%2Fannounce&tr=http%3A%2F%2Ftracker2.itzmx.com%3A6961%2Fannounce&tr=udp%3A%2F%2Ftracker1.itzmx.com%3A8080%2Fannounce&tr=udp%3A%2F%2Ftracker2.itzmx.com%3A6961%2Fannounce&tr=udp%3A%2F%2Ftracker3.itzmx.com%3A6961%2Fannounce&tr=udp%3A%2F%2Ftracker4.itzmx.com%3A2710%2Fannounce&tr=http%3A%2F%2Ftr.bangumi.moe%3A6969%2Fannounce',
    peerId,
  );
  torrent.on<PeerAdded>().listen((peer) {
    print('${peer.peer} added');
  });
  torrent.on<PeerDisconnected>().listen((peer) {
    print('${peer.peer} disconnected');
  });
  final metadata = await torrent.getMetaData();
  print(metadata.files[4]);
  torrent.storage = FileTorrentStorage('./example');
  torrent.seekTo(metadata.files[1].offset, metadata.files[1].length);
  torrent.start();
  torrent.on<PieceChecked>().listen((piece) {
    print('${piece.piece} checked');
  });
}
