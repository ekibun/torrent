part of 'package:torrent/torrent.dart';

mixin _Peer0010 on _Peer0003 {
  static const OP_EXTENDED = 20;

  String _client = '';
  String get client => _client;
  int _reqq = 250;

  @override
  Uint8List get _selfReserved => super._selfReserved..[5] |= 0x10;

  bool get isSupportedExtendMessage => (reserved?[5] ?? 0) & 0x10 != 0;

  Map<String, void Function(Uint8List)> get _onExtendMessage => {};

  Map<String, int> _extendMessageId = {};
  final Completer _extendHandshakeCompleter = Completer();
  Future get extendHandshaked => _extendHandshakeCompleter.future;

  void _onExtendHandshake(Map message) {
    if (!_extendHandshakeCompleter.isCompleted) {
      _extendHandshakeCompleter.complete();
    }
    _reqq = message['reqq'] ?? 250;
    final c = message['v'];
    if (c is ByteString) _client = c.utf8;
    _extendMessageId = Map<String, int>.from(message['m'] ?? _extendMessageId);
  }

  @override
  void _onMessage(_PeerManager task, int op, Uint8List data) {
    if (op != OP_EXTENDED) return super._onMessage(task, op, data);
    final extId = data[0];
    if (extId == 0) {
      _onExtendHandshake(Bencode.decode(data, 1));
    } else {
      _onExtendMessage.entries.elementAt(extId - 1).value(data.sublist(1));
    }
  }

  @override
  void _onHandshaked() {
    _extendHandshake().catchError((_) {});
    super._onHandshaked();
  }

  void _sendExtendMessage(String key, Uint8List payload) =>
      sendPacket(OP_EXTENDED, [
        _extendMessageId[key]!,
        ...payload,
      ]);

  Future _extendHandshake() {
    var messageId = 0;
    sendPacket(OP_EXTENDED, [
      0,
      ...Bencode.encode(
          {'m': _onExtendMessage.map((k, v) => MapEntry(k, ++messageId))})
    ]);
    return extendHandshaked;
  }
}
