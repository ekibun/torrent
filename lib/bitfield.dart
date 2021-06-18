import 'dart:typed_data' show Uint8List;

class Bitfield {
  bool haveAll = false;

  Uint8List bytes = Uint8List(0);

  @override
  String toString() =>
      bytes.map((i) => i.toRadixString(2).padLeft(8, '0')).join('');

  void _grow(int bitLength) {
    final byteLength = (bitLength / 8).ceil();
    if (bytes.length < byteLength) {
      bytes = Uint8List(byteLength)..setAll(0, bytes);
    }
  }

  bool isFullfilled(int bitLength) {
    if (haveAll) return true;
    final byteLength = (bitLength / 8).ceil();
    if (bytes.length < byteLength) return false;
    final mask = 0x100 - (1 << (byteLength * 8 - bitLength));
    if (bytes[byteLength - 1] & mask != mask) return false;
    for (var i = 0; i < byteLength - 1; ++i) {
      if (bytes[i] != 0xff) return false;
    }
    return true;
  }

  bool operator [](int index) {
    if (haveAll) return true;
    _grow(index + 1);
    return bytes[index >> 3] & (128 >> (index % 8)) != 0;
  }

  void operator []=(int index, bool bit) {
    _grow(index + 1);
    final byteIndex = index >> 3;
    if (bit) {
      bytes[byteIndex] |= (128 >> (index % 8));
    } else {
      bytes[byteIndex] &= ~(128 >> (index % 8));
    }
  }
}
