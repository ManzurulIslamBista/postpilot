import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/import_export/presentation/postman_export_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_exporter.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_parser.dart';

const _apiKey = 'k3j9f0s8d7f6g5h4j3k2l1z0x9c8v7';

ApiRequestEntity _request(
  String name, {
  String url = 'https://api.test/x',
  RequestAuth auth = const RequestAuth(),
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> queryParams = const [],
  RequestBody body = RequestBody.empty,
}) =>
    ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: name,
      method: HttpMethod.post,
      url: url,
      headers: headers,
      queryParams: queryParams,
      body: body,
      auth: auth,
    );

/// One request per way a credential can be stored, every secret value unique so a leak is easy to see.
final _requests = [
  _request(
    'bearer',
    url: 'https://api.test/x?api_key=$_apiKey&page=1',
    auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'bearer-abc'),
    headers: [
      KeyValueItem(key: 'Authorization', value: 'Bearer hdr-1'),
      KeyValueItem(key: 'X-Api-Key', value: 'key-1'),
      KeyValueItem(key: 'Cookie', value: 'sid=abc'),
      KeyValueItem(key: 'Accept', value: 'application/json'),
    ],
    queryParams: [KeyValueItem(key: 'api_key', value: 'qk-1'), KeyValueItem(key: 'page', value: '2')],
    body: const RequestBody(type: BodyType.raw, rawText: '{"password": "hunter2", "n": 1}'),
  ),
  _request('basic', auth: const RequestAuth(type: AuthType.basic, basicUsername: 'ada', basicPassword: 'pw-basic')),
  _request('digest', auth: const RequestAuth(type: AuthType.digest, basicUsername: 'ada', basicPassword: 'pw-digest')),
  _request('apikey', auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'X-Key', apiKeyValue: 'ak-1')),
  _request(
    'aws',
    auth: const RequestAuth(
      type: AuthType.awsSignatureV4,
      awsAccessKey: 'AKIAIOSFODNN7EXAMPLE',
      awsSecretKey: 'aws-secret',
      awsSessionToken: 'aws-sess',
    ),
  ),
  _request('jwt', auth: const RequestAuth(type: AuthType.jwtBearer, jwtSecret: 'jwt-secret')),
  _request(
    'oauth2',
    auth: const RequestAuth(
      type: AuthType.oauth2,
      oauth2ClientId: 'client-id',
      oauth2ClientSecret: 'oauth-cs',
      oauth2Username: 'ada',
      oauth2Password: 'oauth-pw',
    ),
  ),
  _request(
    'urlencoded',
    body: RequestBody(
      type: BodyType.urlEncoded,
      urlEncodedFields: [KeyValueItem(key: 'client_secret', value: 'enc-1'), KeyValueItem(key: 'grant', value: 'x')],
    ),
  ),
  _request(
    'formdata',
    body: RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'password', value: 'form-1')]),
  ),
  _request(
    'graphql',
    body: const RequestBody(
      type: BodyType.graphql,
      graphqlQuery: 'mutation { login(email: "a@b.c", password: "gq-1") { id } }',
      graphqlVariables: '{"pin": 4321, "user": "ada"}',
    ),
  ),
];

const _secrets = [
  'bearer-abc', 'hdr-1', 'key-1', 'sid=abc', _apiKey, 'qk-1', 'hunter2', 'pw-basic', 'pw-digest', 'ak-1', 'aws-secret', 'aws-sess',
  'jwt-secret', 'oauth-cs', 'oauth-pw', 'enc-1', 'form-1', 'gq-1', '4321', 'coll-token', 'pw-coll', //
];

String _export({bool redact = true}) => PostmanCollectionExporter.export(
      collectionName: 'Secrets',
      folders: const [],
      requests: _requests,
      collectionAuth: const RequestAuth(type: AuthType.bearer, bearerToken: 'coll-token'),
      variables: const [
        CollectionVariableEntity(id: 1, collectionId: 1, key: 'db_password', value: 'pw-coll', enabled: true),
        CollectionVariableEntity(id: 2, collectionId: 1, key: 'baseUrl', value: 'https://x.test', enabled: true),
      ],
      redactSecrets: redact,
    );

Map<String, dynamic> _item(Map<String, dynamic> root, String name) =>
    ((root['item'] as List).cast<Map<String, dynamic>>().firstWhere((i) => i['name'] == name))['request'] as Map<String, dynamic>;

Map<String, String> _auth(Map<String, dynamic> request) {
  final auth = request['auth'] as Map<String, dynamic>;
  return {for (final e in auth[auth['type']] as List) '${e['key']}': '${e['value']}'};
}

void main() {
  group('PostmanCollectionExporter with redactSecrets', () {
    late String json;
    late Map<String, dynamic> root;

    setUp(() {
      json = _export();
      root = jsonDecode(json) as Map<String, dynamic>;
    });

    test('no secret survives anywhere in the file', () {
      for (final secret in _secrets) {
        expect(json, isNot(contains(secret)), reason: secret);
      }
    });

    test('every auth credential becomes a placeholder, and the rest of the auth is kept', () {
      expect(_auth(_item(root, 'bearer'))['token'], '{{bearerToken}}');
      expect(_auth(_item(root, 'basic')), containsPair('password', '{{basicPassword}}'));
      expect(_auth(_item(root, 'basic')), containsPair('username', 'ada'));
      expect(_auth(_item(root, 'digest')), containsPair('password', '{{basicPassword}}'));
      expect(_auth(_item(root, 'apikey')), containsPair('value', '{{apiKey}}'));
      expect(_auth(_item(root, 'apikey')), containsPair('key', 'X-Key'));
      final aws = _auth(_item(root, 'aws'));
      expect(aws['secretKey'], '{{awsSecretKey}}');
      expect(aws['sessionToken'], '{{awsSessionToken}}');
      expect(aws['accessKey'], 'AKIAIOSFODNN7EXAMPLE', reason: 'the access key id is an identifier');
      expect(aws['region'], 'us-east-1');
      expect(_auth(_item(root, 'jwt'))['secret'], '{{jwtSecret}}');
      final oauth = _auth(_item(root, 'oauth2'));
      expect(oauth['clientSecret'], '{{oauth2ClientSecret}}');
      expect(oauth['password'], '{{oauth2Password}}');
      expect(oauth['clientId'], 'client-id');
      expect(oauth['username'], 'ada');
      expect((root['auth'] as Map)['bearer'], [
        {'key': 'token', 'value': '{{bearerToken}}'},
      ]);
    });

    test('secret headers, query parameters, the URL and the bodies are redacted by their names', () {
      final bearer = _item(root, 'bearer');
      expect((bearer['header'] as List).map((h) => '${h['key']}: ${h['value']}'), [
        'Authorization: Bearer {{Authorization}}',
        'X-Api-Key: {{X-Api-Key}}',
        'Cookie: {{Cookie}}',
        'Accept: application/json',
      ]);
      final url = bearer['url'] as Map<String, dynamic>;
      expect(url['raw'], 'https://api.test/x?api_key={{api_key}}&page=1&api_key={{api_key}}&page=2');
      expect((url['query'] as List).map((q) => '${q['key']}=${q['value']}'), ['api_key={{api_key}}', 'page=2']);
      expect((bearer['body'] as Map)['raw'], '{"password": "{{password}}", "n": 1}');

      expect(((_item(root, 'urlencoded')['body'] as Map)['urlencoded'] as List).map((f) => f['value']), ['{{client_secret}}', 'x']);
      expect(((_item(root, 'formdata')['body'] as Map)['formdata'] as List).single['value'], '{{password}}');
      final graphql = (_item(root, 'graphql')['body'] as Map)['graphql'] as Map;
      expect(graphql['query'], 'mutation { login(email: "a@b.c", password: "{{password}}") { id } }');
      expect(graphql['variables'], '{"pin": "{{pin}}", "user": "ada"}');
    });

    test('each placeholder is declared as an empty variable, and a secret variable is emptied', () {
      final variables = {for (final v in root['variable'] as List) '${v['key']}': '${v['value']}'};
      expect(variables['db_password'], '', reason: 'a variable named like a credential keeps its name only');
      expect(variables['baseUrl'], 'https://x.test');
      for (final name in ['bearerToken', 'basicPassword', 'apiKey', 'awsSecretKey', 'jwtSecret', 'oauth2ClientSecret', 'Authorization', 'api_key', 'password', 'pin']) {
        expect(variables, containsPair(name, ''), reason: name);
      }
      expect((root['variable'] as List).length, variables.length, reason: 'no variable is declared twice');
    });

    test('what is not a secret is left exactly as it was', () {
      expect(json, contains('"https://api.test/x"'));
      expect(json, contains('application/json'));
      expect(json, contains('a@b.c'));
      expect(json, contains('client-id'));
    });

    test('the redacted file still imports, with the placeholders as values', () {
      final parsed = PostmanCollectionParser.parse(json);
      final bearer = parsed.items.whereType<PostmanRequestItem>().firstWhere((r) => r.name == 'bearer');
      expect(bearer.auth.type, AuthType.bearer);
      expect(bearer.auth.bearerToken, '{{bearerToken}}');
    });
  });

  group('PostmanCollectionExporter.redact', () {
    test('without the option, the export keeps every value, as before', () {
      final json = _export(redact: false);
      for (final secret in ['bearer-abc', 'hdr-1', 'hunter2', 'pw-basic', 'coll-token', 'pw-coll']) {
        expect(json, contains(secret), reason: secret);
      }
    });

    test('is idempotent and agrees with redactSecrets on export', () {
      final plain = _export(redact: false);
      final once = PostmanCollectionExporter.redact(plain);
      expect(PostmanCollectionExporter.redact(once), once);
      expect(once, _export());
    });

    test('values that already are variables, and empty ones, stay and declare nothing', () {
      final json = PostmanCollectionExporter.export(
        collectionName: 'Templates',
        folders: const [],
        requests: [
          _request(
            'templated',
            auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
            headers: [KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}')],
          ),
          _request('empty', auth: const RequestAuth(type: AuthType.basic, basicUsername: 'ada')),
        ],
        redactSecrets: true,
      );
      final root = jsonDecode(json) as Map<String, dynamic>;
      expect(_auth(_item(root, 'templated'))['token'], '{{token}}');
      expect((_item(root, 'templated')['header'] as List).single['value'], 'Bearer {{token}}');
      expect(_auth(_item(root, 'empty'))['password'], '');
      expect(root.containsKey('variable'), isFalse);
    });

    test('text that is not a Postman file comes back as it was', () {
      expect(PostmanCollectionExporter.redact('not json'), 'not json');
      expect(PostmanCollectionExporter.redact('[1, 2]'), '[1, 2]');
    });
  });

  group('PostmanExportBody', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final copied = <String>[];

    setUp(() {
      copied.clear();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
    });
    tearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    Future<void> pump(WidgetTester tester, String json) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: PostmanExportBody(json: json))),
      ));
    }

    String shown(WidgetTester tester) => tester
        .widget<SelectableText>(find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(SelectableText)))
        .data!;

    testWidgets('starts with the secrets redacted and says so, and copies what it shows', (tester) async {
      await pump(tester, _export(redact: false));

      expect(find.text('Secrets are replaced'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
      expect(shown(tester), contains('{{bearerToken}}'));
      expect(shown(tester), isNot(contains('bearer-abc')));

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(copied.single, _export());
      expect(copied.single, isNot(contains('bearer-abc')));
    });

    testWidgets('turning redaction off warns that secrets are in plain text and shows them', (tester) async {
      await pump(tester, _export(redact: false));

      await tester.tap(find.text('Redact secrets'));
      await tester.pump();

      expect(find.text('Secrets are written in plain text'), findsOneWidget);
      expect(find.text('Secrets are replaced'), findsNothing);
      expect(shown(tester), contains('bearer-abc'));

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(copied.single, _export(redact: false));
    });
  });
}
