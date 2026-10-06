import 'dart:async';
import 'dart:io';
import '../../core/network/upload_body.dart';
import '../../core/network/upload_file_source.dart';
import '../documentation/domain/services/secret_masker.dart';
import 'workspace_runner.dart';

const _maxBodyBytes = 20 * 1024 * 1024;

/// The most a command-line request may upload in files; there is no setting for it here.
const _maxUploadBytes = UploadLimits.defaultMegabytes * 1024 * 1024;

/// Sends a request with `dart:io`. Redirects are followed, the body is capped,
/// and a certificate error stops the request unless the run asked for `--insecure`.
///
/// The files of an upload are looked at before anything is sent (a missing file, or a body over the limit, is an
/// error of the request with the connection never opened) and are then streamed from disk, never loaded whole.
Future<CliResponse> sendWithDartIo(CliRequest request) async {
  final client = HttpClient()..connectionTimeout = request.timeout;
  if (!request.verifySsl) client.badCertificateCallback = (_, _, _) => true;
  final clock = Stopwatch()..start();
  try {
    final upload = request.upload;
    final prepared = upload == null
        ? null
        : await UploadPreparer.prepare(
            upload,
            createUploadFileSource(baseDir: request.baseDir),
            maxBytes: _maxUploadBytes,
            limitHint: 'The command line sends at most ${UploadLimits.describe(_maxUploadBytes)} of files.',
          );
    final call = await client.openUrl(request.method, Uri.parse(request.url));
    request.headers.forEach((name, value) {
      try {
        call.headers.set(name, value);
      } catch (_) {
        // A header Dart refuses (a stray control character) is dropped rather than failing the run.
      }
    });
    final body = request.body;
    if (prepared != null) {
      call.contentLength = prepared.length;
      await call.addStream(prepared.open());
    } else if (body != null && body.isNotEmpty) {
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
  } on HttpException catch (e) {
    // Its text can quote the whole URL (`?token=...` and all); only the message is kept, masked.
    throw 'The HTTP exchange failed: ${SecretMasker.maskMessage(e.message)}';
  } on FormatException catch (e) {
    // `Uri.parse` and the HTTP client append the offending text; the message alone says what is wrong.
    throw 'The request URL is not valid: ${SecretMasker.maskMessage(e.message)}';
  } on TlsException catch (e) {
    throw 'TLS error: ${e.message}';
  } finally {
    client.close(force: true);
  }
}
