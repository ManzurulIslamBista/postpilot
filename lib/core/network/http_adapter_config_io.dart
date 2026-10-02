import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../errors/app_exception.dart';
import 'api_http_response.dart';

/// An adapter over a `dart:io` client that skips certificate checks when
/// [verifySsl] is off and routes requests as [proxy] says.
HttpClientAdapter createNetworkAdapter({required bool verifySsl, required ProxyConfig proxy}) => IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient()..idleTimeout = const Duration(seconds: 3);
        if (!verifySsl) client.badCertificateCallback = (_, _, _) => true;
        client.findProxy = (uri) => proxyDirectiveFor(proxy, uri);
        return client;
      },
    );

/// The `HttpClient.findProxy` answer for [uri]: `DIRECT`, or
/// `PROXY user:password@host:port`. Credentials must travel in that string:
/// `HttpClient.addProxyCredentials` is never consulted when a request is
/// tunnelled through the proxy (every https one), so it would leave those
/// requests unauthenticated.
@visibleForTesting
String proxyDirectiveFor(ProxyConfig proxy, Uri uri) {
  switch (proxy.mode) {
    case ProxyMode.none:
      return 'DIRECT';
    case ProxyMode.system:
      return HttpClient.findProxyFromEnvironment(uri);
    case ProxyMode.custom:
      if (!proxy.isUsableCustom || proxy.bypasses(uri)) return 'DIRECT';
      // Refused here, before `HttpClient` parses the directive: its own error
      // for a broken one quotes the whole directive, password included.
      if (proxy.hasUnsendableCredentials) throw const NetworkException(ProxyConfig.unsendableCredentialsMessage);
      final host = proxy.host.contains(':') && !proxy.host.startsWith('[') ? '[${proxy.host}]' : proxy.host;
      // `HttpClient` rejects credentials with an empty side.
      final credentials = proxy.username.isEmpty || proxy.password.isEmpty ? '' : '${proxy.username}:${proxy.password}@';
      return 'PROXY $credentials$host:${proxy.port}';
  }
}
