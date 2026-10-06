import 'dart:convert';
import 'dart:typed_data';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../defaults/domain/services/header_inheritance.dart';
import '../entities/api_request_entity.dart';
import '../entities/key_value_item.dart';
import '../entities/request_auth.dart';
import '../entities/request_body.dart';
import 'aws_sigv4_signer.dart';
import 'jwt_signer.dart';
import 'resolved_request_spec.dart';
import 'undefined_variables.dart';

/// Resolves `{{variables}}`, encodes the body for its [BodyType], and signs
/// auth headers for every type except Digest (which needs a 401 round-trip
/// first — see `SendRequestUseCase._retryWithDigest`) and OAuth 2.0, whose
/// token is fetched ahead of time by `RequestOAuth2ViewModel` and only
/// applied here from the cache — `build` is synchronous. Shared, through
/// [PrepareRequestUseCase], by [SendRequestUseCase] and the code snippets so
/// "what gets sent" and "what gets printed as a snippet" can never drift apart.
final class RequestSpecBuilder {
  const RequestSpecBuilder();

  /// [inheritedAuth] is the default auth of the nearest folder that sets one,
  /// else the collection's; it only takes effect when the request itself is set
  /// to [AuthType.inherit]. [inheritedHeaders] are the headers the collection
  /// and its folders pass down (already merged, enabled rows only, see
  /// `DefaultsResolver`); the request's own rows override or, when disabled,
  /// switch off an inherited header of the same name (case-insensitive, after
  /// `{{variables}}` in the name are resolved), see `HeaderInheritance`. Header,
  /// query, urlencoded and form-data rows take `{{variables}}` in their keys as
  /// well as their values. With [trimKeysAndValues] those keys and values then
  /// lose their leading and trailing whitespace, and a row whose key is empty by
  /// then is dropped. With [sendNoCache] a `Cache-Control: no-cache` header is
  /// added, unless the request sets a `Cache-Control` of its own (any case).
  ResolvedRequestSpec build(
    ApiRequestEntity request,
    VariableResolver resolver, {
    RequestAuth? inheritedAuth,
    List<KeyValueItem> inheritedHeaders = const [],
    bool trimKeysAndValues = false,
    bool sendNoCache = false,
  }) {
    final tidy = trimKeysAndValues ? _trim : _keep;
    final auth = _resolveNames(request.auth.resolveInherited(inheritedAuth), resolver);
    final url = _buildUrl(request, auth, resolver, tidy);
    final uri = Uri.parse(url);
    final body = _buildBody(request, resolver, tidy);
    final headerRows = _effectiveHeaders(inheritedHeaders, request.headers, resolver, tidy);
    final headers = _buildHeaders(headerRows, auth, resolver, uri, body, request.method.label, tidy);
    if (sendNoCache && !headers.keys.any((name) => name.toLowerCase() == 'cache-control')) {
      headers['Cache-Control'] = 'no-cache';
    }
    return ResolvedRequestSpec(method: request.method.label, url: url, headers: headers, bodyBytes: body.bytes);
  }

  /// The `{{variables}}` [build] would leave in the request as literal text
  /// because no scope defines them (a built-in `{{$guid}}` is defined, and so
  /// is a variable whose value is empty), each with where it is used. Looks at
  /// exactly what [build] reads: enabled rows whose key is not empty, and the
  /// auth of the type in force. [build] itself never throws for these: a code
  /// snippet is still worth printing with `{{baseUrl}}` in it.
  List<UndefinedVariable> undefinedVariables(
    ApiRequestEntity request,
    VariableResolver resolver, {
    RequestAuth? inheritedAuth,
    List<KeyValueItem> inheritedHeaders = const [],
    bool trimKeysAndValues = false,
  }) {
    final tidy = trimKeysAndValues ? _trim : _keep;
    final auth = request.auth.resolveInherited(inheritedAuth);
    final places = <String, List<String>>{};
    final inBody = <String>{};

    void scan(String text, String place, {bool body = false}) {
      for (final name in resolver.undefinedIn(text)) {
        final where = places.putIfAbsent(name, () => []);
        if (!where.contains(place)) where.add(place);
        if (body) inBody.add(name);
      }
    }

    void scanRows(List<KeyValueItem> items, String Function(String key) place, {bool body = false}) {
      for (final item in items) {
        if (!item.enabled) continue;
        final key = tidy(resolver.resolve(item.key));
        if (key.isEmpty) continue;
        scan(item.key, place(key), body: body);
        scan(item.value, place(key), body: body);
      }
    }

    scan(request.url, 'the URL');
    scanRows(request.queryParams, (key) => 'the query parameter "$key"');
    scanRows(_effectiveHeaders(inheritedHeaders, request.headers, resolver, tidy), (key) => 'the "$key" header');
    switch (auth.type) {
      case AuthType.apiKey:
        if (resolver.resolve(auth.apiKeyName).isNotEmpty) {
          scan(auth.apiKeyName, 'the API key name');
          scan(auth.apiKeyValue, 'the API key');
        }
      case AuthType.bearer:
        scan(auth.bearerToken, 'the Bearer token');
      case AuthType.basic:
        scan(auth.basicUsername, 'the Basic auth user name');
        scan(auth.basicPassword, 'the Basic auth password');
      case AuthType.digest:
        scan(auth.basicUsername, 'the Digest auth user name');
        scan(auth.basicPassword, 'the Digest auth password');
      case AuthType.awsSignatureV4:
        scan(auth.awsAccessKey, 'the AWS access key');
        scan(auth.awsSecretKey, 'the AWS secret key');
        scan(auth.awsRegion, 'the AWS region');
        scan(auth.awsService, 'the AWS service');
        scan(auth.awsSessionToken, 'the AWS session token');
      case AuthType.jwtBearer:
        scan(auth.jwtSecret, 'the JWT secret');
        scan(auth.jwtPayload, 'the JWT payload');
        scan(auth.jwtHeaderPrefix, 'the JWT header prefix');
      case AuthType.oauth2: // the cached token is sent as it is, not resolved
      case AuthType.none:
      case AuthType.inherit:
        break;
    }

    final body = request.body;
    switch (body.type) {
      case BodyType.none:
        break;
      case BodyType.raw:
        scan(body.rawText, 'the request body', body: true);
      case BodyType.urlEncoded:
        scanRows(body.urlEncodedFields, (key) => 'the form field "$key"', body: true);
      case BodyType.formData:
        scanRows(body.formFields, (key) => 'the form field "$key"', body: true);
      case BodyType.graphql:
        scan(body.graphqlQuery, 'the GraphQL query', body: true);
        scan(body.graphqlVariables, 'the GraphQL variables', body: true);
    }

    return [for (final e in places.entries) UndefinedVariable(e.key, e.value, inBody: inBody.contains(e.key))];
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

  /// The header rows that are sent, before auth: what the collection and its folders pass down, then the
  /// request's own. A request's row of an inherited name (enabled or not) takes it over; see
  /// `HeaderInheritance`. Names are compared as they are sent, with their `{{variables}}` resolved.
  List<KeyValueItem> _effectiveHeaders(
    List<KeyValueItem> inherited,
    List<KeyValueItem> own,
    VariableResolver resolver,
    _Tidy tidy,
  ) {
    if (inherited.isEmpty) return own;
    return HeaderInheritance.merge([inherited, own], nameOf: (key) => tidy(resolver.resolve(key)));
  }

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
    List<KeyValueItem> headerRows,
    RequestAuth auth,
    VariableResolver resolver,
    Uri uri,
    _EncodedBody body,
    String method,
    _Tidy tidy,
  ) {
    final headers = {for (final row in _rows(headerRows, resolver, tidy)) row.key: row.value};
    // Header names are case-insensitive: a user's `content-type` row wins.
    if (body.contentType != null && !headers.keys.any((name) => name.toLowerCase() == 'content-type')) {
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
          payload: _jwtPayload(resolver.resolve(auth.jwtPayload)),
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
          'variables': variables.isEmpty ? <String, dynamic>{} : _graphqlVariables(variables),
        });
        return _EncodedBody(bytes: utf8.encode(payload), contentType: 'application/json');
    }
  }

  /// A `FormatException` here would be read by the UI as a URL or connection
  /// problem, so bad JSON in the user's own fields is reported as what it is.
  Object? _graphqlVariables(String text) {
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw InvalidRequestException('The GraphQL variables are not valid JSON (${e.message}).');
    }
  }

  Map<String, dynamic> _jwtPayload(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw InvalidRequestException('The JWT payload is not valid JSON (${e.message}).');
    }
    if (decoded is! Map) throw const InvalidRequestException('The JWT payload must be a JSON object.');
    return decoded.cast<String, dynamic>();
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
