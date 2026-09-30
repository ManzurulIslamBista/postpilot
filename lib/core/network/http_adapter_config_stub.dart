import 'package:dio/dio.dart';
import 'api_http_response.dart';

/// The browser owns certificate checks and proxying, so [verifySsl] and
/// [proxy] cannot apply here; this is simply the platform's own adapter.
HttpClientAdapter createNetworkAdapter({required bool verifySsl, required ProxyConfig proxy}) => HttpClientAdapter();
