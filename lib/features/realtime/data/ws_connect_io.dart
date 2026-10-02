import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Desktop and mobile can send custom headers (an Authorization, a cookie) in the handshake.
WebSocketChannel connect(Uri uri, {Map<String, String> headers = const {}, List<String> protocols = const []}) =>
    IOWebSocketChannel.connect(uri, headers: headers.isEmpty ? null : headers, protocols: protocols.isEmpty ? null : protocols);
