import 'dart:convert' as _convert;
import 'dart:math' show Random;
import 'dart:typed_data' show Uint8List, BytesBuilder;

class ByteString {
  final Uint8List bytes;
  String? _utf8;
  String? _hex;

  String get utf8 {
    _utf8 ??= _convert.utf8.decode(bytes, allowMalformed: true);
    return _utf8!;
  }

  @override
  String toString() {
    _hex ??= bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _hex!;
  }

  int get length => bytes.length;

  int operator [](int i) => bytes[i];

  @override
  bool operator ==(Object? b) =>
      b is String ? b == utf8 : b.toString() == toString();

  @override
  int get hashCode => toString().hashCode;

  ByteString(List<int> bytes)
      : bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  ByteString.str(String str)
      : _utf8 = str,
        bytes = Uint8List.fromList(_convert.utf8.encode(str));

  ByteString.int(int value, int length)
      : bytes = Uint8List.fromList(List.generate(
            length, (i) => (value >> (8 * (length - i - 1))) & 0xff));

  ByteString.hex(String str)
      : bytes = Uint8List.fromList(List.generate(str.length ~/ 2,
            (i) => int.parse(str.substring(i * 2, (i + 1) * 2), radix: 16)));

  static ByteString rand(int length) {
    final rand = Random();
    return ByteString(List.generate(length, (_) => rand.nextInt(256)));
  }

  int toInt() {
    return bytes.reduce((value, element) => (value << 8) + element);
  }
}

class BencodeScanner {
  Uint8List data;
  var pos = 0;
  BencodeScanner(this.data);

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
          dict[key.utf8] = value;
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
        return int.parse(String.fromCharCodes(data, begin, pos++));
      default:
        final begin = pos - 1;
        while (String.fromCharCode(data[pos]) != ':') {
          pos++;
        }
        final len = int.parse(String.fromCharCodes(data, begin, pos++));
        pos += len;
        return ByteString(data.sublist(pos - len, pos));
    }
  }
}

class Bencode {
  static Uint8List encode(dynamic data) {
    final ret = BytesBuilder();
    if (data is int) {
      ret.add(_convert.ascii.encode('i${data.toString()}e'));
    } else if (data is Map) {
      ret.add(_convert.ascii.encode('d'));
      for (var item in data.entries) {
        ret.add(encode(item.key));
        ret.add(encode(item.value));
      }
      ret.add(_convert.ascii.encode('e'));
    } else if (data is List) {
      ret.add(_convert.ascii.encode('l'));
      for (var item in data) {
        ret.add(encode(item));
      }
      ret.add(_convert.ascii.encode('e'));
    } else if (data is ByteString || data is String) {
      final str = data is ByteString ? data.bytes : _convert.utf8.encode(data);
      ret.add(_convert.ascii.encode('${str.length}:'));
      ret.add(str);
    }
    return ret.toBytes();
  }

  static dynamic decode(Uint8List data, [int pos = 0]) {
    final scanner = BencodeScanner(data)..pos = pos;
    return scanner.next();
  }
}
