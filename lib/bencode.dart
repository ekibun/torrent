import 'dart:convert' as _convert;
import 'dart:math' show Random;
import 'dart:typed_data' show Uint8List, BytesBuilder;

class ByteString {
  final Uint8List bytes;
  String? _utf8;
  String? _hex;

  @override
  String toString() {
    _utf8 ??= _convert.utf8.decode(bytes, allowMalformed: true);
    return _utf8!;
  }

  String get hex {
    _hex ??= bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _hex!;
  }

  int get length => bytes.length;

  int operator [](int i) => bytes[i];

  @override
  bool operator ==(Object? b) => b is String
      ? b == toString()
      : b is ByteString
          ? b.hex == hex
          : false;

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

mixin BencodeObject<T extends BencodeObject<T>> {
  abstract String encodeKey;
  T decode(dynamic data);
  dynamic encode();
}

class BencodeScanner {
  Uint8List data;
  final List<BencodeObject>? extend;
  var pos = 0;
  BencodeScanner(this.data, {this.extend});

  Object? next() {
    switch (String.fromCharCode(data[pos++])) {
      case 'x':
        final key = next().toString();
        final value = next();
        return extend?.firstWhere((o) => o.encodeKey == key).decode(value);
      case 'e':
        return null;
      case 'd':
        final dict = <String, dynamic>{};
        while (true) {
          final key = next();
          if (key == null) return dict;
          final value = next();
          dict[key.toString()] = value;
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
    if (data is BencodeObject) {
      ret.add(_convert.ascii.encode('x'));
      ret.add(encode(data.encodeKey));
      ret.add(encode(data.encode()));
    } else if (data is int) {
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
    } else if (data == null) {
      ret.add(_convert.ascii.encode('e'));
    } else {
      print('Unsupported $data');
      ret.add(encode(data.toString()));
    }
    return ret.toBytes();
  }

  static dynamic decode(
    Uint8List data, {
    int pos = 0,
    List<BencodeObject>? extend,
  }) {
    final scanner = BencodeScanner(data, extend: extend)..pos = pos;
    return scanner.next();
  }
}
