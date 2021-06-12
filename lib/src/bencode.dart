import 'dart:convert';
import 'dart:typed_data';

class ByteString {
  final List<int> bytes;
  String? _utf8;

  String get string {
    _utf8 ??= utf8.decode(bytes, allowMalformed: true);
    return _utf8!;
  }

  int get length => bytes.length;

  int operator [](int i) => bytes[i];

  ByteString(this.bytes);
  ByteString.str(String str)
      : _utf8 = str,
        bytes = utf8.encode(str);

  ByteString.int(int value, int length)
      : bytes = Uint8List.fromList(List.generate(
            length, (i) => (value >> (8 * (length - i - 1))) & 0xff));

  ByteString.hex(String str)
      : bytes = Uint8List.fromList(List.generate(str.length ~/ 2,
            (i) => int.parse(str.substring(i * 2, (i + 1) * 2), radix: 16)));

  @override
  String toString() {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  int toInt() {
    return bytes.reduce((value, element) => (value << 8) + element);
  }
}

class _Scanner {
  Uint8List data;
  var pos = 0;
  _Scanner(this.data);

  Object? next() {
    switch (String.fromCharCode(data[pos++])) {
      case 'e':
        return null;
      case 'd':
        final dict = <String, dynamic>{};
        while (true) {
          final key = next();
          if (!(key is ByteString)) return dict;
          final value = next();
          dict[key.string] = value;
        }
      case 'l':
        final list = <dynamic>[];
        while (true) {
          final value = next();
          if (value == null) return list;
          list.add(value);
        }
      case 'i':
        final begin = pos;
        while (String.fromCharCode(data[pos]) != 'e') {
          pos++;
        }
        pos++;
        return int.parse(String.fromCharCodes(data, begin, pos - 1));
      default:
        final begin = pos - 1;
        while (String.fromCharCode(data[pos]) != ':') {
          pos++;
        }
        pos++;
        final len = int.parse(String.fromCharCodes(data, begin, pos - 1));
        pos += len;
        return ByteString(data.sublist(pos - len, pos));
    }
  }
}

class Bencode {
  static Uint8List encode(dynamic data) {
    final ret = BytesBuilder();
    if (data is int) {
      ret.add(ascii.encode('i${data.toString()}e'));
    } else if (data is Map) {
      ret.add(ascii.encode('d'));
      for (var item in data.entries) {
        ret.add(encode(item.key));
        ret.add(encode(item.value));
      }
      ret.add(ascii.encode('e'));
    } else if (data is List) {
      ret.add(ascii.encode('l'));
      for (var item in data) {
        ret.add(encode(item));
      }
      ret.add(ascii.encode('e'));
    } else {
      final str =
          data is ByteString ? data.bytes : utf8.encode(data.toString());
      ret.add(ascii.encode('${str.length}:'));
      ret.add(str);
    }
    return ret.toBytes();
  }

  static dynamic decode(Uint8List data) {
    final scanner = _Scanner(data);
    return scanner.next();
  }
}
