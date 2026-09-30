import 'dart:convert';
import '../../../../../core/enums/auth_type.dart';
import '../../../../../core/enums/body_type.dart';
import '../../../../collections/domain/entities/collection_entity.dart';
import '../../../../collections/domain/entities/collection_variable_entity.dart';
import '../../entities/api_request_entity.dart';
import '../../entities/key_value_item.dart';
import '../../entities/request_auth.dart';
import '../../entities/request_body.dart';

/// Serializes a collection back to Postman Collection v2.1 JSON — the
/// mirror image of [PostmanCollectionParser], so a round-trip through
/// export-then-import is lossless for everything this app itself supports.
abstract final class PostmanCollectionExporter {
  static String export({
    required String collectionName,
    required List<FolderEntity> folders,
    required List<ApiRequestEntity> requests,
    List<CollectionVariableEntity> variables = const [],
    RequestAuth? collectionAuth,
  }) {
    final tree = _buildTree(null, folders, requests);
    final auth = collectionAuth == null ? null : _authOf(collectionAuth);
    return const JsonEncoder.withIndent('  ').convert({
      'info': {
        'name': collectionName,
        'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
      },
      'item': tree,
      'auth': ?auth,
      if (variables.isNotEmpty)
        'variable': [for (final v in variables) {'key': v.key, 'value': v.value, 'disabled': !v.enabled}],
    });
  }

  static List<Map<String, dynamic>> _buildTree(
    int? parentFolderId,
    List<FolderEntity> folders,
    List<ApiRequestEntity> requests,
  ) {
    final items = <Map<String, dynamic>>[];
    for (final folder in folders.where((f) => f.parentFolderId == parentFolderId)) {
      items.add({
        'name': folder.name,
        'item': _buildTree(folder.id, folders, requests),
      });
    }
    for (final request in requests.where((r) => r.folderId == parentFolderId)) {
      items.add(_requestItem(request));
    }
    return items;
  }

  static Map<String, dynamic> _requestItem(ApiRequestEntity request) {
    final auth = _authOf(request.auth);
    return {
      'name': request.name,
      'request': {
        'method': request.method.label,
        'header': [for (final h in request.headers) {'key': h.key, 'value': h.value, 'disabled': !h.enabled}],
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
