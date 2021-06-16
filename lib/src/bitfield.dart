import 'dart:typed_data';

class Bitfield {
  Uint8List bytes = Uint8List(0);

  void _grow(int bitLength) {
    final byteLength = (bitLength / 8).ceil();
    if (bytes.length < byteLength) {
      bytes = Uint8List(byteLength)..setAll(0, bytes);
    }
  }

  bool operator [](int index) {
    _grow(index);
    return bytes[index >> 3] & (128 >> (index % 8)) != 0;
  }

  void operator []=(int index, bool bit) {
    _grow(index);
    final byteIndex = index >> 3;
    if (bit) {
      bytes[byteIndex] |= (128 >> (index % 8));
    } else {
      bytes[byteIndex] &= ~(128 >> (index % 8));
    }
  }
}