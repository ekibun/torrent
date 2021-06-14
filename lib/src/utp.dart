
// import 'dart:io';
// import 'dart:math';

// enum Utp_state { SYN_SENT }

// class Utp {
//   Utp_state state = Utp_state.SYN_SENT;
//   int seq_nr = 1;
//   int conn_id_recv = -1;
//   int conn_id_send = -1;

//   Socket _socket;

//   Utp(InternetAddress ip, int port) {
//     conn_id_recv = Random().nextInt(0xffff);
//     conn_id_send = conn_id_recv + 1;
//   }

//   static start() async {
//     final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
//   }
// }