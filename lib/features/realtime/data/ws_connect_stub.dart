import 'package:web_socket_channel/web_socket_channel.dart';

/// A browser cannot set handshake headers: only the URL and sub-protocols can be given.
/// Closing the channel is all the abort it offers.
({WebSocketChannel channel, void Function() abort}) connect(
  Uri uri, {
  Map<String, String> headers = const {},
  List<String> protocols = const [],
}) {
  final channel = WebSocketChannel.connect(uri, protocols: protocols.isEmpty ? null : protocols);
  return (channel: channel, abort: () {});
}
