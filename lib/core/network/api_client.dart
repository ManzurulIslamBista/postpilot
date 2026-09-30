import 'api_http_response.dart';

abstract interface class ApiClient {
  Future<ApiHttpResponse> send(ApiRequestSpec spec);
}
