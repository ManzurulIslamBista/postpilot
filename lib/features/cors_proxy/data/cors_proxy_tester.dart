import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/cors_proxy_diagnosis.dart';
import '../domain/cors_proxy_protocol.dart';
import '../domain/cors_proxy_settings.dart';
import 'cors_reachability.dart';

/// Calls the proxy's health endpoint and says, in words, why it cannot be used when it cannot. Uses a client of its own, not
/// the app's: the app's client would send the health check through the proxy.
final class CorsProxyTester {
  /// Replaces the platform's HTTP adapter, for a test.
  final HttpClientAdapter? adapter;

  /// Replaces the browser's `no-cors` probe, for a test.
  final Future<bool?> Function(Uri url) probe;

  /// Where the app runs, in a browser; null elsewhere.
  final String? pageOrigin;

  final Duration timeout;

  CorsProxyTester({this.adapter, Future<bool?> Function(Uri url)? probe, this.pageOrigin, this.timeout = const Duration(seconds: 6)})
      : probe = probe ?? probeReachable;

  Future<CorsProxyTestResult> run(CorsProxySettings settings) async {
    final base = settings.baseUri;
    if (base == null) return CorsProxyDiagnosis.invalidUrl(settings.urlProblem!);
    final url = base.replace(path: CorsProxyProtocol.healthPath);
    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
      followRedirects: false,
    ));
    if (adapter != null) dio.httpClientAdapter = adapter!;
    try {
      final token = settings.token.trim();
      final response = await dio.getUri<String>(
        url,
        options: Options(headers: {if (token.isNotEmpty) CorsProxyProtocol.tokenHeader: token}),
      );
      return _fromAnswer(base, response);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return CorsProxyDiagnosis.timedOut(base);
      }
      return CorsProxyDiagnosis.unreachable(base, reachable: await probe(url), pageOrigin: pageOrigin);
    } finally {
      dio.close(force: true);
    }
  }

  CorsProxyTestResult _fromAnswer(Uri base, Response<String> response) {
    final status = response.statusCode ?? 0;
    final code = response.headers.value(CorsProxyProtocol.errorHeader.toLowerCase());
    Object? json;
    try {
      json = jsonDecode(response.data ?? '');
    } on FormatException {
      json = null;
    }
    if (status == 200 && code == null && json is Map && json['ok'] == true) {
      return CorsProxyDiagnosis.connected(
        base,
        version: json['version'] is String ? json['version'] as String : null,
        allowedOrigin: json['allowedOrigin'] is String ? json['allowedOrigin'] as String : null,
      );
    }
    // Only the header proves the answer is the proxy's own: any other server may send a JSON body with an "error" field.
    return CorsProxyDiagnosis.refused(base, status, code, pageOrigin: pageOrigin);
  }
}
