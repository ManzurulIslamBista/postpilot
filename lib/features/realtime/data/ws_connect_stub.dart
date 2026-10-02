import 'package:web_socket_channel/web_socket_channel.dart';

/// A browser cannot set handshake headers: only the URL and sub-protocols can be given.
WebSocketChannel connect(Uri uri, {Map<String, String> headers = const {}, List<String> protocols = const []}) =>
    WebSocketChannel.connect(uri, protocols: protocols.isEmpty ? null : protocols);
