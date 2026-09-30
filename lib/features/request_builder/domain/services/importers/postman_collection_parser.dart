import 'dart:convert';
import '../../../../../core/enums/auth_type.dart';
import '../../../../../core/enums/body_type.dart';
import '../../../../../core/enums/http_method.dart';
import '../../entities/key_value_item.dart';
import '../../entities/request_auth.dart';
import '../../entities/request_body.dart';

sealed class PostmanItem {
  final String name;
  const PostmanItem(this.name);
}

final class PostmanFolderItem extends PostmanItem {
  final List<PostmanItem> children;
  const PostmanFolderItem(super.name, this.children);
}

final class PostmanRequestItem extends PostmanItem {
  final HttpMethod method;
  final String url;
  final List<KeyValueItem> headers;

  /// Only the disabled `url.query` entries: the enabled ones are already
  /// part of [url] (Postman's `raw`).
  final List<KeyValueItem> queryParams;
  final RequestBody body;
  final RequestAuth auth;
  const PostmanRequestItem(
    super.name, {
    required this.method,
    required this.url,
    required this.headers,
    this.queryParams = const [],
    required this.body,
    required this.auth,
  });
}

final class ParsedPostmanCollection {
  final String name;
  final List<PostmanItem> items;

  /// The collection-level `variable` array: [KeyValueItem.enabled] is the
  /// inverse of Postman's `disabled` flag.
  final List<KeyValueItem> variables;

  /// The root `auth` block; null when the export has none, in which case
  /// requests that inherit have nothing to inherit from.
  final RequestAuth? auth;
  const ParsedPostmanCollection(this.name, this.items, {this.variables = const [], this.auth});
}

/// Parses a Postman Collection v2.x export. Covers what real-world exports
/// actually contain: nested folders, collection variables, raw/urlencoded/
/// formdata/graphql bodies, and the auth types this app itself supports
/// (bearer/basic/api key/digest/AWS SigV4/JWT/OAuth 2.0). Anything else —
/// oauth1/hawk/ntlm/etc, file-type form fields, `event` scripts — is skipped,
/// not rejected: a partially-imported collection beats a failed import.
///
/// Postman omits `auth` on a request that inherits, so a missing block means
/// "inherit". This app only has collection-level auth to inherit from, so a
/// folder's own `auth` is copied down onto the requests beneath it that set
/// none of their own.
abstract final class PostmanCollectionParser {
  static ParsedPostmanCollection parse(String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final name = (root['info'] as Map?)?['name'] as String? ?? 'Imported collection';
    final items = (root['item'] as List? ?? const []).map((i) => _parseItem(i, null)).whereType<PostmanItem>().toList();
    return ParsedPostmanCollection(
      name,
      items,
      variables: _variablesOf(root['variable']),
      auth: _explicitAuthOf(root['auth']),
    );
  }

  static List<KeyValueItem> _variablesOf(dynamic variables) {
    if (variables is! List) return const [];
    return variables
        .whereType<Map>()
        .where((v) => v['key'] is String && (v['key'] as String).isNotEmpty)
        .map((v) => KeyValueItem(key: v['key'] as String, value: '${v['value'] ?? ''}', enabled: v['disabled'] != true))
        .toList();
  }

  static PostmanItem? _parseItem(dynamic raw, RequestAuth? folderAuth) {
    final map = raw as Map<String, dynamic>;
    final name = map['name'] as String? ?? 'Untitled';

    if (map['request'] == null) {
      final childAuth = _explicitAuthOf(map['auth']) ?? folderAuth;
      final children =
          (map['item'] as List? ?? const []).map((i) => _parseItem(i, childAuth)).whereType<PostmanItem>().toList();
      return PostmanFolderItem(name, children);
    }

    final request = map['request'] as Map<String, dynamic>;
    return PostmanRequestItem(
      name,
      method: HttpMethod.fromString(request['method'] as String? ?? 'GET'),
      url: _urlOf(request['url']),
      headers: _headersOf(request['header']),
      queryParams: _disabledQueryParamsOf(request['url']),
      body: _bodyOf(request['body']),
      auth: _explicitAuthOf(request['auth']) ?? folderAuth ?? const RequestAuth(type: AuthType.inherit),
    );
  }

  static String _urlOf(dynamic url) {
    if (url is String) return url;
    if (url is Map) return url['raw'] as String? ?? '';
    return '';
  }

  static List<KeyValueItem> _disabledQueryParamsOf(dynamic url) {
    if (url is! Map) return const [];
    return _keyValueListOf(url['query']).where((p) => !p.enabled).toList();
  }

  static List<KeyValueItem> _headersOf(dynamic headers) {
    if (headers is! List) return const [];
    return headers
        .whereType<Map>()
        .map((h) => KeyValueItem(
              key: h['key'] as String? ?? '',
              value: h['value'] as String? ?? '',
              enabled: h['disabled'] != true,
            ))
        .toList();
  }

  static List<KeyValueItem> _keyValueListOf(dynamic list) {
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .where((e) => e['type'] != 'file')
        .map((e) => KeyValueItem(
              key: e['key'] as String? ?? '',
              value: e['value'] as String? ?? '',
              enabled: e['disabled'] != true,
            ))
        .toList();
  }

  static RequestBody _bodyOf(dynamic body) {
    if (body is! Map) return RequestBody.empty;
    switch (body['mode'] as String?) {
      case 'raw':
        final language = ((body['options'] as Map?)?['raw'] as Map?)?['language'] as String?;
        return RequestBody(
          type: BodyType.raw,
          rawText: body['raw'] as String? ?? '',
          rawContentType: switch (language) {
            'json' => RawContentType.json,
            'xml' => RawContentType.xml,
            'html' => RawContentType.html,
            'javascript' => RawContentType.javascript,
            _ => RawContentType.text,
          },
        );
      case 'urlencoded':
        return RequestBody(type: BodyType.urlEncoded, urlEncodedFields: _keyValueListOf(body['urlencoded']));
      case 'formdata':
        return RequestBody(type: BodyType.formData, formFields: _keyValueListOf(body['formdata']));
      case 'graphql':
        final graphql = body['graphql'] as Map?;
        final variables = graphql?['variables'];
        return RequestBody(
          type: BodyType.graphql,
          graphqlQuery: graphql?['query'] as String? ?? '',
          graphqlVariables: variables is String ? variables : jsonEncode(variables ?? {}),
        );
      default:
        return RequestBody.empty;
    }
  }

  /// Null when [auth] is absent, which is how Postman says "inherit".
  static RequestAuth? _explicitAuthOf(dynamic auth) => auth is Map ? _authOf(auth) : null;

  static RequestAuth _authOf(Map auth) {
    final type = auth['type'] as String?;
    Map<String, dynamic> field(String key) {
      final list = (auth[key] as List? ?? const []).whereType<Map>();
      return {for (final e in list) (e['key'] as String? ?? ''): e['value']};
    }

    switch (type) {
      case 'noauth':
        return const RequestAuth(type: AuthType.none);
      case 'bearer':
        return RequestAuth(type: AuthType.bearer, bearerToken: '${field('bearer')['token'] ?? ''}');
      case 'basic':
        final f = field('basic');
        return RequestAuth(type: AuthType.basic, basicUsername: '${f['username'] ?? ''}', basicPassword: '${f['password'] ?? ''}');
      case 'digest':
        final f = field('digest');
        return RequestAuth(type: AuthType.digest, basicUsername: '${f['username'] ?? ''}', basicPassword: '${f['password'] ?? ''}');
      case 'apikey':
        final f = field('apikey');
        return RequestAuth(
          type: AuthType.apiKey,
          apiKeyName: '${f['key'] ?? ''}',
          apiKeyValue: '${f['value'] ?? ''}',
          apiKeyLocation: f['in'] == 'query' ? ApiKeyLocation.query : ApiKeyLocation.header,
        );
      case 'awsv4':
        final f = field('awsv4');
        return RequestAuth(
          type: AuthType.awsSignatureV4,
          awsAccessKey: '${f['accessKey'] ?? ''}',
          awsSecretKey: '${f['secretKey'] ?? ''}',
          awsRegion: '${f['region'] ?? 'us-east-1'}',
          awsService: '${f['service'] ?? 'execute-api'}',
          awsSessionToken: '${f['sessionToken'] ?? ''}',
        );
      case 'jwt':
        final f = field('jwt');
        return RequestAuth(
          type: AuthType.jwtBearer,
          jwtSecret: '${f['secret'] ?? ''}',
          jwtPayload: f['payload'] is String ? f['payload'] as String : jsonEncode(f['payload'] ?? {}),
          jwtAlgorithm: JwtAlgorithm.values.firstWhere(
            (a) => a.label == (f['algorithm'] as String? ?? 'HS256'),
            orElse: () => JwtAlgorithm.hs256,
          ),
          jwtHeaderPrefix: '${f['headerPrefix'] ?? 'Bearer'}',
        );
      case 'oauth2':
        final f = field('oauth2');
        return RequestAuth(
          type: AuthType.oauth2,
          oauth2GrantType: switch (f['grant_type']) {
            'password_credentials' => OAuth2GrantType.password,
            'authorization_code' || 'authorization_code_with_pkce' => OAuth2GrantType.authorizationCodePkce,
            _ => OAuth2GrantType.clientCredentials,
          },
          oauth2AccessTokenUrl: '${f['accessTokenUrl'] ?? ''}',
          oauth2AuthorizationUrl: '${f['authUrl'] ?? ''}',
          oauth2RedirectUri: '${f['redirect_uri'] ?? ''}',
          oauth2ClientId: '${f['clientId'] ?? ''}',
          oauth2ClientSecret: '${f['clientSecret'] ?? ''}',
          oauth2Scope: '${f['scope'] ?? ''}',
          oauth2Username: '${f['username'] ?? ''}',
          oauth2Password: '${f['password'] ?? ''}',
          oauth2Audience: '${f['audience'] ?? ''}',
          oauth2ClientAuthentication:
              f['client_authentication'] == 'body' ? OAuth2ClientAuthentication.body : OAuth2ClientAuthentication.basicHeader,
        );
      default:
        return const RequestAuth(type: AuthType.none);
    }
  }
}
