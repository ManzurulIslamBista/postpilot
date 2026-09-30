import 'dart:convert';
import 'dart:typed_data';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../entities/api_request_entity.dart';
import '../entities/key_value_item.dart';
import '../entities/request_auth.dart';
import '../entities/request_body.dart';
import 'aws_sigv4_signer.dart';
import 'jwt_signer.dart';
import 'resolved_request_spec.dart';

/// Resolves `{{variables}}`, encodes the body for its [BodyType], and signs
/// auth headers for every type except Digest (which needs a 401 round-trip
/// first — see `SendRequestUseCase._retryWithDigest`) and OAuth 2.0, whose
/// token is fetched ahead of time by `RequestOAuth2ViewModel` and only
/// applied here from the cache — `build` is synchronous. Shared, through
/// [PrepareRequestUseCase], by [SendRequestUseCase] and the code snippets so
/// "what gets sent" and "what gets printed as a snippet" can never drift apart.
final class RequestSpecBuilder {
  const RequestSpecBuilder();

  /// [inheritedAuth] is the collection's default auth; it only takes effect
  /// when the request itself is set to [AuthType.inherit]. Header, query,
  /// urlencoded and form-data rows take `{{variables}}` in their keys as well
  /// as their values. With [trimKeysAndValues] those keys and values then lose
  /// their leading and trailing whitespace, and a row whose key is empty by
  /// then is dropped. With [sendNoCache] a `Cache-Control: no-cache` header is
  /// added, unless the request sets a `Cache-Control` of its own (any case).
  ResolvedRequestSpec build(
    ApiRequestEntity request,
    VariableResolver resolver, {
    RequestAuth? inheritedAuth,
    bool trimKeysAndValues = false,
    bool sendNoCache = false,
  }) {
    final tidy = trimKeysAndValues ? _trim : _keep;
    final auth = _resolveNames(request.auth.resolveInherited(inheritedAuth), resolver);
    final url = _buildUrl(request, auth, resolver, tidy);
    final uri = Uri.parse(url);
    final body = _buildBody(request, resolver, tidy);
    final headers = _buildHeaders(request, auth, resolver, uri, body, request.method.label, tidy);
    if (sendNoCache && !headers.keys.any((name) => name.toLowerCase() == 'cache-control')) {
      headers['Cache-Control'] = 'no-cache';
    }
    return ResolvedRequestSpec(method: request.method.label, url: url, headers: headers, bodyBytes: body.bytes);
  }

  /// The API key's name and the JWT prefix are text the request sends too, so
  /// they take `{{variables}}` like the values do.
  RequestAuth _resolveNames(RequestAuth auth, VariableResolver resolver) => auth.copyWith(
        apiKeyName: resolver.resolve(auth.apiKeyName),
        jwtHeaderPrefix: resolver.resolve(auth.jwtHeaderPrefix),
      );

  /// The enabled rows of [items] with their keys and values resolved and
  /// tidied; a row whose key is then empty is dropped. Pairs rather than a map
  /// because a query param may repeat (`tag=a&tag=b`).
  List<MapEntry<String, String>> _rows(List<KeyValueItem> items, VariableResolver resolver, _Tidy tidy) => [
        for (final item in items)
          if (item.enabled)
            if (tidy(resolver.resolve(item.key)) case final key when key.isNotEmpty)
              MapEntry(key, tidy(resolver.resolve(item.value))),
      ];

  static String _keep(String text) => text;
  static String _trim(String text) => text.trim();

  static final _hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

  /// A query param may repeat (`tag=a&tag=b`), so params stay a list of pairs.
  /// A param overrides same-named entries already in the URL's own query.
  String _buildUrl(ApiRequestEntity request, RequestAuth auth, VariableResolver resolver, _Tidy tidy) {
    final params = _rows(request.queryParams, resolver, tidy);
    if (auth.type == AuthType.apiKey && auth.apiKeyLocation == ApiKeyLocation.query && auth.apiKeyName.isNotEmpty) {
      params
        ..removeWhere((p) => p.key == auth.apiKeyName)
        ..add(MapEntry(auth.apiKeyName, resolver.resolve(auth.apiKeyValue)));
    }
    final base = _withScheme(resolver.resolve(request.url));
    if (params.isEmpty) return base;
    final uri = Uri.parse(base);
    final overridden = {for (final p in params) p.key};
    final query = [
      for (final e in uri.queryParametersAll.entries)
        if (!overridden.contains(e.key))
          for (final value in e.value) MapEntry(e.key, value),
      ...params,
    ];
    final encoded = query.map((p) => '${Uri.encodeQueryComponent(p.key)}=${Uri.encodeQueryComponent(p.value)}');
    return uri.replace(query: encoded.join('&')).toString();
  }

  /// Like Postman, assumes `http://` when the scheme is left off — `Uri.parse`
  /// would otherwise read `localhost:3000/x` as the scheme `localhost`.
  String _withScheme(String url) {
    final trimmed = url.trim();
    return trimmed.isEmpty || _hasScheme.hasMatch(trimmed) ? trimmed : 'http://$trimmed';
  }

  Map<String, String> _buildHeaders(
    ApiRequestEntity request,
    RequestAuth auth,
    VariableResolver resolver,
    Uri uri,
    _EncodedBody body,
    String method,
    _Tidy tidy,
  ) {
    final headers = {for (final row in _rows(request.headers, resolver, tidy)) row.key: row.value};
    if (body.contentType != null && !headers.containsKey('Content-Type')) {
      headers['Content-Type'] = body.contentType!;
    }
    _applyAuth(auth, headers, resolver, uri, body.bytes, method);
    return headers;
  }

  void _applyAuth(
    RequestAuth auth,
    Map<String, String> headers,
    VariableResolver resolver,
    Uri uri,
    List<int>? body,
    String method,
  ) {
    switch (auth.type) {
      case AuthType.apiKey:
        if (auth.apiKeyLocation == ApiKeyLocation.header && auth.apiKeyName.isNotEmpty) {
          headers[auth.apiKeyName] = resolver.resolve(auth.apiKeyValue);
        }
      case AuthType.bearer:
        headers['Authorization'] = 'Bearer ${resolver.resolve(auth.bearerToken)}';
      case AuthType.basic:
        final creds = '${resolver.resolve(auth.basicUsername)}:${resolver.resolve(auth.basicPassword)}';
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(creds))}';
      case AuthType.digest:
        break; // needs a 401 challenge first — see SendRequestUseCase._retryWithDigest
      case AuthType.awsSignatureV4:
        final signer = AwsSigV4Signer(
          accessKey: resolver.resolve(auth.awsAccessKey),
          secretKey: resolver.resolve(auth.awsSecretKey),
          region: resolver.resolve(auth.awsRegion),
          service: resolver.resolve(auth.awsService),
          sessionToken: resolver.resolve(auth.awsSessionToken),
        );
        headers.addAll(signer.sign(method: method, uri: uri, headers: headers, body: body ?? const []));
      case AuthType.jwtBearer:
        final token = JwtSigner.sign(
          secret: resolver.resolve(auth.jwtSecret),
          algorithm: auth.jwtAlgorithm,
          payload: (jsonDecode(resolver.resolve(auth.jwtPayload)) as Map).cast<String, dynamic>(),
        );
        headers['Authorization'] = '${auth.jwtHeaderPrefix} $token'.trim();
      case AuthType.oauth2:
        if (auth.oauth2AccessToken.isNotEmpty) headers['Authorization'] = 'Bearer ${auth.oauth2AccessToken}';
      case AuthType.none:
      case AuthType.inherit:
        break;
    }
  }

  _EncodedBody _buildBody(ApiRequestEntity request, VariableResolver resolver, _Tidy tidy) {
    final body = request.body;
    switch (body.type) {
      case BodyType.none:
        return const _EncodedBody(bytes: null, contentType: null);
      case BodyType.raw:
        if (body.rawText.isEmpty) return const _EncodedBody(bytes: null, contentType: null);
        return _EncodedBody(
          bytes: utf8.encode(resolver.resolve(body.rawText)),
          contentType: body.rawContentType.mimeType,
        );
      case BodyType.urlEncoded:
        final encoded = _rows(body.urlEncodedFields, resolver, tidy)
            .map((f) => '${Uri.encodeQueryComponent(f.key)}=${Uri.encodeQueryComponent(f.value)}')
            .join('&');
        return _EncodedBody(bytes: utf8.encode(encoded), contentType: 'application/x-www-form-urlencoded');
      case BodyType.formData:
        return _buildMultipart(body, resolver, tidy);
      case BodyType.graphql:
        final variables = resolver.resolve(body.graphqlVariables).trim();
        final payload = jsonEncode({
          'query': resolver.resolve(body.graphqlQuery),
          'variables': variables.isEmpty ? <String, dynamic>{} : jsonDecode(variables),
        });
        return _EncodedBody(bytes: utf8.encode(payload), contentType: 'application/json');
    }
  }

  _EncodedBody _buildMultipart(RequestBody body, VariableResolver resolver, _Tidy tidy) {
    final boundary = '----PostPilotBoundary${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final buffer = BytesBuilder();
    for (final field in _rows(body.formFields, resolver, tidy)) {
      buffer.add(utf8.encode('--$boundary\r\n'));
      buffer.add(utf8.encode('Content-Disposition: form-data; name="${field.key}"\r\n\r\n'));
      buffer.add(utf8.encode('${field.value}\r\n'));
    }
    buffer.add(utf8.encode('--$boundary--\r\n'));
    return _EncodedBody(bytes: buffer.toBytes(), contentType: 'multipart/form-data; boundary=$boundary');
  }
}

typedef _Tidy = String Function(String text);

final class _EncodedBody {
  final List<int>? bytes;
  final String? contentType;
  const _EncodedBody({required this.bytes, required this.contentType});
}
