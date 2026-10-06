import 'dart:convert';
import '../../../../../core/enums/auth_type.dart';
import '../../../../../core/enums/body_type.dart';
import '../../../../collections/domain/entities/collection_entity.dart';
import '../../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../../collections/domain/services/collection_order.dart';
import '../../../../defaults/domain/entities/defaults_chain.dart';
import '../../../../defaults/domain/entities/level_defaults.dart';
import '../../../../defaults/domain/services/defaults_resolver.dart';
import '../../../../defaults/domain/services/header_inheritance.dart';
import '../../../../git_sync/domain/services/secret_names.dart';
import '../../../../git_sync/domain/services/secret_text.dart';
import '../../entities/api_request_entity.dart';
import '../../entities/key_value_item.dart';
import '../../entities/request_auth.dart';
import '../../entities/request_body.dart';

/// Serializes a collection back to Postman Collection v2.1 JSON — the
/// mirror image of [PostmanCollectionParser], so a round-trip through
/// export-then-import is lossless for everything this app itself supports.
///
/// The file holds every token, password and API key in plain text, so it must be
/// checked before it is shared. With [redactSecrets] (or [redact] on a finished
/// file) each of them is replaced by a `{{variable}}` placeholder instead.
///
/// What the collection and its folders pass down ([defaults]): a folder's `auth` and `variable`
/// list are written on the folder, where Postman has them, and a request that inherits writes no
/// `auth` of its own, so Postman inherits it from the nearest folder just as this app does.
/// Postman has no header inheritance, so the headers a request inherits are written into each
/// request, explicitly, after the ones it overrides or switches off are taken out. The default tests
/// are not written (neither are the requests' own).
abstract final class PostmanCollectionExporter {
  static String export({
    required String collectionName,
    required List<FolderEntity> folders,
    required List<ApiRequestEntity> requests,
    List<CollectionVariableEntity> variables = const [],
    RequestAuth? collectionAuth,
    DefaultsTree? defaults,
    bool redactSecrets = false,
  }) {
    final tree = _buildTree(null, folders, requests, defaults);
    final auth = collectionAuth == null ? null : _authOf(collectionAuth);
    final json = const JsonEncoder.withIndent('  ').convert({
      'info': {
        'name': collectionName,
        'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
      },
      'item': tree,
      'auth': ?auth,
      if (variables.isNotEmpty)
        'variable': [for (final v in variables) {'key': v.key, 'value': v.value, 'disabled': !v.enabled}],
    });
    return redactSecrets ? redact(json) : json;
  }

  /// [postmanJson], as [export] writes it, with every credential replaced by a `{{variable}}`
  /// placeholder (`{{bearerToken}}`, `{{basicPassword}}`, `{{Authorization}}`, `{{api_key}}`...): the
  /// secrets of the auth settings (bearer token, basic and digest password, API key value, AWS secret
  /// key and session token, JWT secret, OAuth client secret and password), the values of secret headers,
  /// query parameters and form fields, secret values inside the URL and the raw, GraphQL and urlencoded
  /// bodies, and the values of collection variables named like credentials (emptied). Each placeholder
  /// is declared as an empty collection variable, so it only has to be filled in after importing.
  /// Values that already are `{{variables}}` stay. Text that is not a Postman file comes back unchanged.
  static String redact(String postmanJson) {
    final Object? root;
    try {
      root = jsonDecode(postmanJson);
    } on FormatException {
      return postmanJson;
    }
    if (root is! Map<String, dynamic>) return postmanJson;
    _SecretRedactor().document(root);
    return const JsonEncoder.withIndent('  ').convert(root);
  }

  /// The `item` list of [parentFolderId] (null = top level): its folders and requests interleaved in the
  /// collection's canonical order (see `CollectionOrder`), so Postman lists them as the sidebar does.
  static List<Map<String, dynamic>> _buildTree(
    int? parentFolderId,
    List<FolderEntity> folders,
    List<ApiRequestEntity> requests,
    DefaultsTree? defaults, [
    CollectionOrder? order,
  ]) {
    final canonical = order ??
        CollectionOrder.of(
          folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
          requests: [for (final r in requests) (id: r.id, folderId: r.folderId, orderIndex: r.orderIndex)],
        );
    final items = <Map<String, dynamic>>[];
    for (final entry in canonical.childrenOf(parentFolderId)) {
      if (!entry.isFolder) {
        items.add(_requestItem(requests[entry.index], defaults));
        continue;
      }
      final folder = folders[entry.index];
      final level = defaults?.folderDefaults[folder.id] ?? LevelDefaults.empty;
      final auth = level.auth == null ? null : _authOf(level.auth!);
      items.add({
        'name': folder.name,
        'auth': ?auth,
        if (level.variables.isNotEmpty)
          'variable': [
            for (final v in level.variables)
              {'key': v.key, 'value': v.value, if (v.isSecret) 'type': 'secret', 'disabled': !v.enabled},
          ],
        'item': _buildTree(folder.id, folders, requests, defaults, canonical),
      });
    }
    return items;
  }

  static Map<String, dynamic> _requestItem(ApiRequestEntity request, DefaultsTree? defaults) {
    final auth = _authOf(request.auth);
    final inherited = defaults == null
        ? const <KeyValueItem>[]
        : DefaultsResolver.resolve(defaults.chainFor(request.folderId)).headerRows;
    final headers = HeaderInheritance.materialize(inherited, request.headers);
    return {
      'name': request.name,
      'request': {
        'method': request.method.label,
        'header': [for (final h in headers) {'key': h.key, 'value': h.value, 'disabled': !h.enabled}],
        'url': _urlOf(request),
        'body': _bodyOf(request.body),
        'auth': ?auth,
      },
    };
  }

  /// `raw` has the enabled Params appended, as Postman shows and sends it;
  /// `query` lists every param, disabled ones flagged.
  static Map<String, dynamic> _urlOf(ApiRequestEntity request) {
    final enabled = [
      for (final p in request.queryParams)
        if (p.enabled && p.key.isNotEmpty) '${p.key}=${p.value}',
    ];
    final separator = request.url.contains('?') ? '&' : '?';
    return {
      'raw': enabled.isEmpty ? request.url : '${request.url}$separator${enabled.join('&')}',
      if (request.queryParams.isNotEmpty) 'query': _keyValueList(request.queryParams),
    };
  }

  static Map<String, dynamic>? _bodyOf(RequestBody body) => switch (body.type) {
        BodyType.none => null,
        BodyType.raw => {
            'mode': 'raw',
            'raw': body.rawText,
            'options': {
              'raw': {'language': body.rawContentType.name},
            },
          },
        BodyType.urlEncoded => {'mode': 'urlencoded', 'urlencoded': _keyValueList(body.urlEncodedFields)},
        BodyType.formData => {'mode': 'formdata', 'formdata': _keyValueList(body.formFields)},
        BodyType.graphql => {
            'mode': 'graphql',
            'graphql': {'query': body.graphqlQuery, 'variables': body.graphqlVariables},
          },
      };

  static List<Map<String, dynamic>> _keyValueList(List<KeyValueItem> items) =>
      [for (final i in items) {'key': i.key, 'value': i.value, 'disabled': !i.enabled}];

  /// `null` for [AuthType.inherit]: Postman writes no `auth` for a request that
  /// inherits, and an explicit `noauth` would override the collection's auth.
  static Map<String, dynamic>? _authOf(RequestAuth auth) => switch (auth.type) {
        AuthType.none => {'type': 'noauth'},
        AuthType.inherit => null,
        AuthType.bearer => {
            'type': 'bearer',
            'bearer': [
              {'key': 'token', 'value': auth.bearerToken},
            ],
          },
        AuthType.basic => {
            'type': 'basic',
            'basic': [
              {'key': 'username', 'value': auth.basicUsername},
              {'key': 'password', 'value': auth.basicPassword},
            ],
          },
        AuthType.digest => {
            'type': 'digest',
            'digest': [
              {'key': 'username', 'value': auth.basicUsername},
              {'key': 'password', 'value': auth.basicPassword},
            ],
          },
        AuthType.apiKey => {
            'type': 'apikey',
            'apikey': [
              {'key': 'key', 'value': auth.apiKeyName},
              {'key': 'value', 'value': auth.apiKeyValue},
              {'key': 'in', 'value': auth.apiKeyLocation.name == 'query' ? 'query' : 'header'},
            ],
          },
        AuthType.awsSignatureV4 => {
            'type': 'awsv4',
            'awsv4': [
              {'key': 'accessKey', 'value': auth.awsAccessKey},
              {'key': 'secretKey', 'value': auth.awsSecretKey},
              {'key': 'region', 'value': auth.awsRegion},
              {'key': 'service', 'value': auth.awsService},
              {'key': 'sessionToken', 'value': auth.awsSessionToken},
            ],
          },
        AuthType.jwtBearer => {
            'type': 'jwt',
            'jwt': [
              {'key': 'secret', 'value': auth.jwtSecret},
              {'key': 'payload', 'value': auth.jwtPayload},
              {'key': 'algorithm', 'value': auth.jwtAlgorithm.label},
              {'key': 'headerPrefix', 'value': auth.jwtHeaderPrefix},
            ],
          },
        // The cached access token is deliberately left out: it is short-lived
        // and Postman re-fetches its own anyway.
        AuthType.oauth2 => {
            'type': 'oauth2',
            'oauth2': [
              {
                'key': 'grant_type',
                'value': switch (auth.oauth2GrantType) {
                  OAuth2GrantType.clientCredentials => 'client_credentials',
                  OAuth2GrantType.password => 'password_credentials',
                  OAuth2GrantType.authorizationCodePkce => 'authorization_code_with_pkce',
                },
              },
              {'key': 'accessTokenUrl', 'value': auth.oauth2AccessTokenUrl},
              {'key': 'authUrl', 'value': auth.oauth2AuthorizationUrl},
              {'key': 'redirect_uri', 'value': auth.oauth2RedirectUri},
              {'key': 'clientId', 'value': auth.oauth2ClientId},
              {'key': 'clientSecret', 'value': auth.oauth2ClientSecret},
              {'key': 'scope', 'value': auth.oauth2Scope},
              {'key': 'username', 'value': auth.oauth2Username},
              {'key': 'password', 'value': auth.oauth2Password},
              {'key': 'audience', 'value': auth.oauth2Audience},
              {
                'key': 'client_authentication',
                'value': auth.oauth2ClientAuthentication == OAuth2ClientAuthentication.body ? 'body' : 'header',
              },
              {'key': 'challengeAlgorithm', 'value': 'S256'},
              {'key': 'addTokenTo', 'value': 'header'},
            ],
          },
      };
}

/// The places of an exported Postman document that can hold a credential, and what replaces it.
final class _SecretRedactor {
  /// Per auth type, which `{key, value}` entries hold a credential, and the variable that replaces each.
  static const _authSecrets = {
    'bearer': {'token': 'bearerToken'},
    'basic': {'password': 'basicPassword'},
    'digest': {'password': 'basicPassword'},
    'apikey': {'value': 'apiKey'},
    'awsv4': {'secretKey': 'awsSecretKey', 'sessionToken': 'awsSessionToken'},
    'jwt': {'secret': 'jwtSecret'},
    'oauth2': {'clientSecret': 'oauth2ClientSecret', 'password': 'oauth2Password'},
  };

  static final _scheme = RegExp(r'^\s*(?:Bearer|Basic|Digest|Token|ApiKey)\s+', caseSensitive: false);
  static final _illegal = RegExp(r'[^A-Za-z0-9_.$-]+');

  /// The placeholder variables used, in the order they first were.
  final used = <String>[];

  void document(Map<String, dynamic> root) {
    _auth(root['auth']);
    _items(root['item']);
    final variables = root['variable'];
    final list = variables is List ? variables : <Object?>[];
    for (final variable in list) {
      if (variable is! Map) continue;
      final key = variable['key'];
      final value = variable['value'];
      if (key is String && value is String && SecretNames.looksSecretKey(key) && SecretNames.hasLiteralSecret(value)) {
        variable['value'] = '';
      }
    }
    final declared = {for (final v in list) if (v is Map) v['key']};
    for (final name in used) {
      if (!declared.contains(name)) list.add({'key': name, 'value': ''});
    }
    if (list.isNotEmpty) root['variable'] = list;
  }

  /// The variable name for [raw] (a header, field or auth setting), made legal for `{{name}}`.
  String name(String raw) {
    final cleaned = raw.trim().replaceAll(_illegal, '_');
    final variable = cleaned.isEmpty ? 'secret' : cleaned;
    if (!used.contains(variable)) used.add(variable);
    return variable;
  }

  String _placeholder(String raw) => '{{${name(raw)}}}';

  void _items(Object? items) {
    if (items is! List) return;
    for (final item in items) {
      if (item is! Map) continue;
      _items(item['item']);
      // A folder carries an `auth` and its own variables, like the collection.
      _auth(item['auth']);
      _variables(item['variable']);
      final request = item['request'];
      if (request is Map) _request(request);
    }
  }

  /// The values of variables named like credentials, or typed `secret`, are emptied.
  void _variables(Object? variables) {
    if (variables is! List) return;
    for (final variable in variables) {
      if (variable is! Map) continue;
      final key = variable['key'];
      final value = variable['value'];
      final secret = variable['type'] == 'secret' || (key is String && SecretNames.looksSecretKey(key));
      if (secret && value is String && SecretNames.hasLiteralSecret(value)) variable['value'] = '';
    }
  }

  void _request(Map request) {
    _auth(request['auth']);
    _pairs(request['header'], SecretNames.isSecretHeader, keepScheme: true);

    final url = request['url'];
    if (url is Map) {
      final raw = url['raw'];
      if (raw is String) url['raw'] = SecretText.blankUrl(raw, placeholder: name);
      _pairs(url['query'], SecretNames.isSecretQuery);
    } else if (url is String) {
      request['url'] = SecretText.blankUrl(url, placeholder: name);
    }

    final body = request['body'];
    if (body is! Map) return;
    final raw = body['raw'];
    if (raw is String) body['raw'] = SecretText.blankBody(raw, placeholder: name);
    _pairs(body['urlencoded'], SecretNames.looksSecretKey);
    _pairs(body['formdata'], SecretNames.looksSecretKey);
    final graphql = body['graphql'];
    if (graphql is Map) {
      for (final field in const ['query', 'variables']) {
        final text = graphql[field];
        if (text is String) graphql[field] = SecretText.blankBody(text, placeholder: name);
      }
    }
  }

  /// `{key, value}` entries (headers, parameters, form fields) whose [isSecret] name has a literal value.
  /// With [keepScheme], `Bearer abc` becomes `Bearer {{Authorization}}`, not `{{Authorization}}`.
  void _pairs(Object? pairs, bool Function(String name) isSecret, {bool keepScheme = false}) {
    if (pairs is! List) return;
    for (final pair in pairs) {
      if (pair is! Map) continue;
      final key = pair['key'];
      final value = pair['value'];
      if (key is! String || value is! String || !isSecret(key) || !SecretNames.hasLiteralSecret(value)) continue;
      final scheme = keepScheme ? _scheme.firstMatch(value)?.group(0) ?? '' : '';
      pair['value'] = '$scheme${_placeholder(key)}';
    }
  }

  void _auth(Object? auth) {
    if (auth is! Map) return;
    final secrets = _authSecrets[auth['type']];
    final entries = auth[auth['type']];
    if (secrets == null || entries is! List) return;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final variable = secrets[entry['key']];
      final value = entry['value'];
      if (variable != null && value is String && SecretNames.hasLiteralSecret(value)) {
        entry['value'] = _placeholder(variable);
      }
    }
  }
}
