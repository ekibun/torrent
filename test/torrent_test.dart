import 'dart:io';

import 'package:test/test.dart';
import 'package:torrent/src/bencode.dart';

void main() {
  group('bencode', () {
    test('decodeTorrent', () async {
      final data = await File('test/test.torrent').readAsBytes();
      expect(ByteString.int(2333, 2).toInt(), 2333);
      final Map decode = Bencode.decode(data);
      final encode = Bencode.encode(decode);
      final decode2 = Bencode.decode(encode);
      expect(decode.length, decode2.length);
    });
  });
}
