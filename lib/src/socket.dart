import 'dart:io';
import 'dart:typed_data';

abstract class PeerSocket {
  void Function(Uint8List)? onData;
  void add(List<int> data);
  InternetAddress get address;
  int get port;
  Future close();
}

class TcpPeerSocket extends PeerSocket {
  final Socket _socket;
  TcpPeerSocket._(this._socket) {
    _socket.done.onError((error, stackTrace) {});
    _socket.handleError((_) {}).listen((data) {
      try {
        onData?.call(data);
      } catch (e, stack) {
        print('$e\n$stack');
      }
    });
  }

  static Future<TcpPeerSocket> connect(host, int port,
          {sourceAddress, Duration? timeout}) =>
      Socket.connect(host, port, sourceAddress: sourceAddress, timeout: timeout)
          .then((socket) => TcpPeerSocket._(socket));

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  Future close() => _socket.close();

  @override
  InternetAddress get address => _socket.address;

  @override
  int get port => _socket.port;
}
