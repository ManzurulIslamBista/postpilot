import 'dart:convert';
import '../../../../../core/enums/auth_type.dart';
import '../../../../../core/enums/body_type.dart';
import '../../../../../core/enums/http_method.dart';
import '../../../../../core/errors/app_exception.dart';
import '../../../../scripting/domain/entities/assertion_entity.dart';
import '../../../../scripting/domain/entities/extractor_entity.dart';
import '../../entities/key_value_item.dart';
import '../../entities/request_auth.dart';
import '../../entities/request_body.dart';
import 'postman_script_translator.dart';

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

  /// The checks and variable extractions its `test` scripts (and those of the
  /// folders and collection above it) translate to, parents first.
  final List<AssertionEntity> assertions;
  final List<ExtractorEntity> extractors;
  const PostmanRequestItem(
    super.name, {
    required this.method,
    required this.url,
    required this.headers,
    this.queryParams = const [],
    required this.body,
    required this.auth,
    this.assertions = const [],
    this.extractors = const [],
  });
}

/// Something in the export that PostPilot has no equivalent for ([skipped]),
/// or that it imported with a difference worth knowing about.
final class PostmanImportNote {
  final bool skipped;

  /// One sentence, naming where it was found. Never holds a value, so it cannot leak a secret.
  final String message;
  const PostmanImportNote({required this.skipped, required this.message});
}

final class ParsedPostmanCollection {
  final String name;
  final List<PostmanItem> items;

  /// The collection-level `variable` array: [KeyValueItem.enabled] is the
  /// inverse of Postman's `disabled` flag. Folder-level variables follow, since
  /// this app has collection variables only.
  final List<KeyValueItem> variables;

  /// The root `auth` block; null when the export has none, in which case
  /// requests that inherit have nothing to inherit from.
  final RequestAuth? auth;

  /// What was left out or changed, in the order it was met.
  final List<PostmanImportNote> notes;
  const ParsedPostmanCollection(this.name, this.items, {this.variables = const [], this.auth, this.notes = const []});

  int get skippedCount => notes.where((n) => n.skipped).length;
  int get folderCount => _count(items, (_) => 1, folders: true);
  int get requestCount => _count(items, (_) => 1, folders: false);
  int get assertionCount => _count(items, (request) => request.assertions.length, folders: false);
  int get extractorCount => _count(items, (request) => request.extractors.length, folders: false);

  /// Sums [perRequest] over the requests, or counts the folders when [folders] is set.
  static int _count(List<PostmanItem> items, int Function(PostmanRequestItem) perRequest, {required bool folders}) {
    var total = 0;
    for (final item in items) {
      switch (item) {
        case PostmanFolderItem():
          total += (folders ? 1 : 0) + _count(item.children, perRequest, folders: folders);
        case PostmanRequestItem():
          if (!folders) total += perRequest(item);
      }
    }
    return total;
  }
}

/// Parses a Postman Collection v2.x export. Covers what real-world exports
/// actually contain: nested folders, collection and folder variables,
/// `:path` variables, raw/urlencoded/formdata/graphql bodies, the auth types
/// this app itself supports (bearer/basic/api key/digest/AWS SigV4/JWT/OAuth
/// 2.0) and the common `pm.test` / `pm.environment.set` test scripts, which
/// become the request's assertions and extractors (see
/// [PostmanScriptTranslator]). Anything else — oauth1/hawk/ntlm/etc,
/// file-type form fields, pre-request scripts, statements it cannot translate,
/// `protocolProfileBehavior` — is skipped, not rejected, and reported in
/// [ParsedPostmanCollection.notes]: a partially-imported collection beats a
/// failed import, but only if it says what is missing.
///
/// Postman omits `auth` on a request that inherits, so a missing block means
/// "inherit". This app only has collection-level auth to inherit from, so a
/// folder's own `auth` is copied down onto the requests beneath it that set
/// none of their own. A folder's or the collection's `test` script runs after
/// every request below it in Postman, so what it translates to is copied down
/// the same way.
abstract final class PostmanCollectionParser {
  static ParsedPostmanCollection parse(String json) {
    // A leading BOM is not JSON, but the format detector accepts such a file.
    final Object? root = jsonDecode(json.replaceFirst('﻿', '').trim());
    if (root is! Map) {
      throw const ImportException('this JSON is not a Postman collection (expected an object with "info" and "item").');
    }
    return _Parser().parse(root);
  }
}

/// What a folder or the collection passes down to what is inside it.
final class _Scope {
  final RequestAuth? auth;
  final List<AssertionEntity> assertions;
  final List<ExtractorEntity> extractors;
  const _Scope({this.auth, this.assertions = const [], this.extractors = const []});
}

final class _Parser {
  final _notes = <PostmanImportNote>[];
  final _variables = <KeyValueItem>[];

  void _skip(String message) => _notes.add(PostmanImportNote(skipped: true, message: message));
  void _adjust(String message) => _notes.add(PostmanImportNote(skipped: false, message: message));

  ParsedPostmanCollection parse(Map root) {
    final info = root['info'];
    final name = info is Map ? info['name'] : null;
    _variables.addAll(_variablesOf(root['variable']));
    // The collection's own auth is stored as the collection auth that requests inherit at send time, so it is
    // not copied onto them; its test script, like a folder's, is.
    final collectionAuth = _explicitAuthOf(root['auth'], 'The collection');
    final scripts = _scriptsOf(root['event'], 'The collection');
    final scope = _Scope(assertions: scripts.assertions, extractors: scripts.extractors);
    final rawItems = root['item'];
    final items = [
      if (rawItems is List)
        for (final raw in rawItems) ?_parseItem(raw, scope),
    ];
    return ParsedPostmanCollection(
      name is String && name.isNotEmpty ? name : 'Imported collection',
      items,
      variables: _variables,
      auth: collectionAuth,
      notes: _notes,
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

  /// A folder's variables join the collection's. The first definition of a name wins.
  void _mergeFolderVariables(String folder, dynamic variables) {
    var added = 0;
    for (final variable in _variablesOf(variables)) {
      final known = _variables.where((v) => v.key == variable.key).firstOrNull;
      if (known == null) {
        _variables.add(variable);
        added++;
      } else if (known.value != variable.value || known.enabled != variable.enabled) {
        _skip('Folder "$folder": variable "${variable.key}" is already defined with another value, so it was not imported.');
      }
    }
    if (added > 0) {
      _adjust(
        'Folder "$folder": $added variable${added == 1 ? '' : 's'} imported as collection variable${added == 1 ? '' : 's'} '
        '(PostPilot has no folder-level variables).',
      );
    }
  }

  /// The auth and test scripts [raw] (a folder or the collection) hands down, on top of what it inherits.
  _Scope _scopeOf(Map raw, String label, _Scope parent) {
    final scripts = _scriptsOf(raw['event'], label);
    return _Scope(
      auth: _explicitAuthOf(raw['auth'], label) ?? parent.auth,
      assertions: [...parent.assertions, ...scripts.assertions],
      extractors: [...parent.extractors, ...scripts.extractors],
    );
  }

  PostmanItem? _parseItem(dynamic raw, _Scope parent) {
    if (raw is! Map) {
      _skip('An entry of "item" is not an object, so it was not imported.');
      return null;
    }
    final name = raw['name'] is String ? raw['name'] as String : 'Untitled';
    final requestRaw = raw['request'];

    if (requestRaw == null) {
      final label = 'Folder "$name"';
      _mergeFolderVariables(name, raw['variable']);
      final scope = _scopeOf(raw, label, parent);
      final rawChildren = raw['item'];
      return PostmanFolderItem(name, [
        if (rawChildren is List)
          for (final child in rawChildren) ?_parseItem(child, scope),
      ]);
    }

    final label = 'Request "$name"';
    // `"request": "https://..."` is Postman's short form of a GET with only a URL.
    final request = requestRaw is String ? <String, dynamic>{'method': 'GET', 'url': requestRaw} : requestRaw;
    if (request is! Map) {
      _skip('$label: its "request" is neither an object nor a URL, so it was not imported.');
      return null;
    }

    final profile = raw['protocolProfileBehavior'];
    if (profile is Map && profile.isNotEmpty) {
      _skip('$label: protocolProfileBehavior (${profile.keys.join(', ')}) was not imported.');
    }
    final examples = raw['response'];
    if (examples is List && examples.isNotEmpty) {
      final one = examples.length == 1;
      _skip('$label: ${examples.length} saved example response${one ? ' was' : 's were'} not imported.');
    }

    final own = _scriptsOf(raw['event'], label);
    return PostmanRequestItem(
      name,
      method: HttpMethod.fromString(request['method'] as String? ?? 'GET'),
      url: _urlOf(request['url'], label),
      headers: _headersOf(request['header']),
      queryParams: _disabledQueryParamsOf(request['url']),
      body: _bodyOf(request['body'], label),
      auth: _explicitAuthOf(request['auth'], label) ?? parent.auth ?? const RequestAuth(type: AuthType.inherit),
      assertions: [...parent.assertions, ...own.assertions],
      extractors: [...parent.extractors, ...own.extractors],
    );
  }

  // --- scripts ------------------------------------------------------------------------------

  ScriptTranslation _scriptsOf(dynamic events, String label) {
    if (events is! List) return const ScriptTranslation();
    final assertions = <AssertionEntity>[];
    final extractors = <ExtractorEntity>[];
    for (final event in events.whereType<Map>()) {
      if (event['disabled'] == true) continue;
      final script = _scriptText(event['script']);
      switch (event['listen']) {
        case 'test':
          if (script == null) {
            _skip('$label: a test script loaded from a URL was not imported.');
            continue;
          }
          final translation = PostmanScriptTranslator.translateTests(script);
          assertions.addAll(translation.assertions);
          extractors.addAll(translation.extractors);
          for (final statement in translation.untranslated) {
            _skip('$label: test script statement not converted: $statement');
          }
          for (final change in translation.adjusted) {
            _adjust('$label: $change.');
          }
        case 'prerequest':
          final statements = script == null ? const <String>[] : PostmanScriptTranslator.describeStatements(script);
          if (script != null && statements.isEmpty) continue;
          _skip(
            script == null
                ? '$label: a pre-request script loaded from a URL was not imported.'
                : '$label: pre-request script (${statements.length} statement${statements.length == 1 ? '' : 's'}) was not '
                      'imported, PostPilot has no scripts that run before a request. It starts with: ${statements.first}',
          );
      }
    }
    return ScriptTranslation(assertions: assertions, extractors: extractors);
  }

  /// The script as one text; null when it is only a `src` link or empty of code.
  static String? _scriptText(dynamic script) {
    if (script is String) return script;
    if (script is! Map) return null;
    final exec = script['exec'];
    if (exec is String) return exec;
    if (exec is List) return exec.whereType<String>().join('\n');
    return null;
  }

  // --- request parts ------------------------------------------------------------------------

  String _urlOf(dynamic url, String label) {
    if (url is String) return url;
    if (url is! Map) return '';
    var result = url['raw'] is String && (url['raw'] as String).isNotEmpty ? url['raw'] as String : _composeUrl(url);

    // PostPilot has no `:name` path variables, so the value Postman stores next to the URL goes into it.
    final filled = <String>[];
    final variables = url['variable'];
    if (variables is List) {
      for (final variable in variables.whereType<Map>()) {
        final key = variable['key'];
        if (key is! String || key.isEmpty) continue;
        final segment = RegExp('(?<=/):${RegExp.escape(key)}(?=[/?#]|\$)');
        if (!segment.hasMatch(result)) continue;
        final value = '${variable['value'] ?? ''}';
        if (value.isEmpty) {
          _skip('$label: path variable :$key has no value, so the URL keeps :$key.');
          continue;
        }
        result = result.replaceAll(segment, value);
        filled.add(':$key');
      }
    }
    if (filled.isNotEmpty) {
      _adjust(
        '$label: path variable${filled.length == 1 ? '' : 's'} ${filled.join(', ')} '
        '${filled.length == 1 ? 'was' : 'were'} written into the URL (PostPilot has no :path variables).',
      );
    }
    return result;
  }

  /// A URL from its parts, for exports that carry no `raw`.
  static String _composeUrl(Map url) {
    String joined(dynamic part, String separator) {
      if (part is String) return part;
      if (part is! List) return '';
      return part.map((segment) => segment is Map ? '${segment['value'] ?? ''}' : '$segment').join(separator);
    }

    final host = joined(url['host'], '.');
    final path = joined(url['path'], '/');
    final port = url['port'];
    final query = [
      for (final param in (url['query'] is List ? url['query'] as List : const []).whereType<Map>())
        if (param['disabled'] != true && param['key'] is String)
          param['value'] == null ? '${param['key']}' : '${param['key']}=${param['value']}',
    ];
    if (host.isEmpty && path.isEmpty) return '';
    final protocol = url['protocol'] is String && (url['protocol'] as String).isNotEmpty ? '${url['protocol']}://' : '';
    final portPart = port == null || '$port'.isEmpty ? '' : ':$port';
    final pathPart = path.isEmpty ? '' : (path.startsWith('/') || host.isEmpty ? path : '/$path');
    return '$protocol$host$portPart$pathPart${query.isEmpty ? '' : '?${query.join('&')}'}';
  }

  List<KeyValueItem> _disabledQueryParamsOf(dynamic url) {
    if (url is! Map || url['query'] is! List) return const [];
    return _keyValueListOf(url['query'], 'query parameter', null).where((p) => !p.enabled).toList();
  }

  List<KeyValueItem> _headersOf(dynamic headers) {
    if (headers is String) {
      // The spec also allows the header block as one text of "Name: value" lines.
      return [
        for (final line in headers.split(RegExp(r'\r?\n')))
          if (line.contains(':'))
            KeyValueItem(key: line.substring(0, line.indexOf(':')).trim(), value: line.substring(line.indexOf(':') + 1).trim()),
      ];
    }
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

  /// [label] is null for lists whose file entries need no report (they are only read for the disabled ones).
  List<KeyValueItem> _keyValueListOf(dynamic list, String what, String? label) {
    if (list is! List) return const [];
    final items = <KeyValueItem>[];
    for (final entry in list.whereType<Map>()) {
      if (entry['type'] == 'file') {
        if (label != null) _skip('$label: file $what "${entry['key'] ?? ''}" was not imported (PostPilot form fields hold text only).');
        continue;
      }
      items.add(
        KeyValueItem(
          key: entry['key'] as String? ?? '',
          value: entry['value'] as String? ?? '',
          enabled: entry['disabled'] != true,
        ),
      );
    }
    return items;
  }

  RequestBody _bodyOf(dynamic body, String label) {
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
        return RequestBody(type: BodyType.urlEncoded, urlEncodedFields: _keyValueListOf(body['urlencoded'], 'field', label));
      case 'formdata':
        return RequestBody(type: BodyType.formData, formFields: _keyValueListOf(body['formdata'], 'field', label));
      case 'graphql':
        final graphql = body['graphql'] as Map?;
        final variables = graphql?['variables'];
        return RequestBody(
          type: BodyType.graphql,
          graphqlQuery: graphql?['query'] as String? ?? '',
          graphqlVariables: variables is String ? variables : jsonEncode(variables ?? {}),
        );
      case 'file':
        _skip('$label: a body sent from a file was not imported.');
        return RequestBody.empty;
      default:
        return RequestBody.empty;
    }
  }

  // --- auth ---------------------------------------------------------------------------------

  /// Null when [auth] is absent, which is how Postman says "inherit".
  RequestAuth? _explicitAuthOf(dynamic auth, String label) => auth is Map ? _authOf(auth, label) : null;

  RequestAuth _authOf(Map auth, String label) {
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
        if (type != null) _skip('$label: "$type" authentication is not supported, so it was imported without authentication.');
        return const RequestAuth(type: AuthType.none);
    }
  }
}
