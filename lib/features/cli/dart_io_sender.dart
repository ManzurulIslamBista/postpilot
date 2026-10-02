import 'dart:async';
import 'dart:io';
import 'workspace_runner.dart';

const _maxBodyBytes = 20 * 1024 * 1024;

/// Sends a request with `dart:io`. Redirects are followed, the body is capped,
/// and a certificate error stops the request unless the run asked for `--insecure`.
Future<CliResponse> sendWithDartIo(CliRequest request) async {
  final client = HttpClient()..connectionTimeout = request.timeout;
  if (!request.verifySsl) client.badCertificateCallback = (_, _, _) => true;
  final clock = Stopwatch()..start();
  try {
    final call = await client.openUrl(request.method, Uri.parse(request.url));
    request.headers.forEach((name, value) {
      try {
        call.headers.set(name, value);
      } catch (_) {
        // A header Dart refuses (a stray control character) is dropped rather than failing the run.
      }
    });
    final body = request.body;
    if (body != null && body.isNotEmpty) {
      call.contentLength = body.length;
      call.add(body);
    }
    final response = await call.close().timeout(request.timeout);
    final bytes = <int>[];
    await for (final chunk in response.timeout(request.timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBodyBytes) break;
    }
    final headers = <String, String>{};
    response.headers.forEach((name, values) => headers[name] = values.join(', '));
    return CliResponse(
      statusCode: response.statusCode,
      statusMessage: response.reasonPhrase,
      headers: headers,
      bodyBytes: bytes,
      duration: clock.elapsed,
    );
  } on TimeoutException {
    throw 'Timed out after ${request.timeout.inSeconds}s';
  } on HandshakeException catch (e) {
    throw 'TLS error: ${e.message}. Use --insecure to skip certificate checks.';
  } on SocketException catch (e) {
    throw "Can't reach the server: ${e.message}";
  } finally {
    client.close(force: true);
  }
}
