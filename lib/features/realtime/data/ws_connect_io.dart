import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Desktop and mobile can send custom headers (an Authorization, a cookie) in the handshake.
///
/// [abort] gives up a connection that is still being opened: it closes the HTTP client the
/// handshake runs on, which drops the connection (closing only the channel would wait for the
/// server to finish the upgrade first). After the upgrade it is not needed.
({WebSocketChannel channel, void Function() abort}) connect(
  Uri uri, {
  Map<String, String> headers = const {},
  List<String> protocols = const [],
}) {
  final client = HttpClient();
  final channel = IOWebSocketChannel.connect(
    uri,
    headers: headers.isEmpty ? null : headers,
    protocols: protocols.isEmpty ? null : protocols,
    customClient: client,
  );
  return (channel: channel, abort: () => client.close(force: true));
}
