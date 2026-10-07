import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';
import 'package:postpilot/features/workplace/domain/services/credential_keeper.dart';

Map<String, dynamic> _auth({String value = '', String type = 'apiKey', String bearer = ''}) => {
  'type': type,
  'apiKeyName': 'access-token',
  'apiKeyValue': value,
  'bearerToken': bearer,
};

Map<String, dynamic> _workspace({
  required Map<String, dynamic> collectionAuth,
  List<Map<String, dynamic>> requests = const [],
  List<Map<String, dynamic>> envVars = const [],
}) => {
  'globals': <Map<String, dynamic>>[],
  'environments': [
    {'name': 'Testing', 'variables': envVars},
  ],
  'collections': [
    {'name': 'API', 'auth': collectionAuth, 'variables': <Map<String, dynamic>>[], 'requests': requests},
  ],
};

void main() {
  group('CredentialKeeper', () {
    test('a pull with a blank collection credential keeps the {{reference}} the device has', () {
      final current = _workspace(collectionAuth: _auth(value: '{{accessToken}}'));
      final pulled = _workspace(collectionAuth: _auth());
      final kept = CredentialKeeper.keep(pulled, current);
      expect((kept['collections'] as List).first['auth']['apiKeyValue'], '{{accessToken}}');
    });

    test('a missing credential key is filled too (a file pushed before the key was kept)', () {
      final current = _workspace(collectionAuth: _auth(value: '{{accessToken}}'));
      final pulled = _workspace(collectionAuth: {'type': 'apiKey', 'apiKeyName': 'access-token'});
      final kept = CredentialKeeper.keep(pulled, current);
      expect((kept['collections'] as List).first['auth']['apiKeyValue'], '{{accessToken}}');
    });

    test('a value the pulled file sets wins, and an auth of another type is left alone', () {
      final current = _workspace(collectionAuth: _auth(value: '{{old}}'));
      final set = CredentialKeeper.keep(_workspace(collectionAuth: _auth(value: '{{shared}}')), current);
      expect((set['collections'] as List).first['auth']['apiKeyValue'], '{{shared}}');
      final other = CredentialKeeper.keep(_workspace(collectionAuth: _auth(type: 'bearer')), current);
      expect((other['collections'] as List).first['auth']['apiKeyValue'], '');
    });

    test('request credentials and secret variables come back; ordinary blank variables stay blank', () {
      final request = {'name': 'Me', 'method': 'get', 'url': '{{baseUrl}}/me', 'auth': _auth(type: 'bearer', bearer: '{{accessToken}}')};
      final blankRequest = {'name': 'Me', 'method': 'get', 'url': '{{baseUrl}}/me', 'auth': _auth(type: 'bearer')};
      final current = _workspace(
        collectionAuth: _auth(),
        requests: [request],
        envVars: [
          {'key': 'accessToken', 'value': 'abc.def', 'secret': true, 'enabled': true},
          {'key': 'lang', 'value': 'en', 'secret': false, 'enabled': true},
        ],
      );
      final pulled = _workspace(
        collectionAuth: _auth(),
        requests: [blankRequest],
        envVars: [
          {'key': 'accessToken', 'value': '', 'secret': true, 'enabled': true},
          {'key': 'lang', 'value': '', 'secret': false, 'enabled': true},
        ],
      );
      final kept = CredentialKeeper.keep(pulled, current);
      final req = ((kept['collections'] as List).first['requests'] as List).first;
      expect(req['auth']['bearerToken'], '{{accessToken}}');
      final vars = ((kept['environments'] as List).first['variables'] as List).cast<Map>();
      expect(vars.firstWhere((v) => v['key'] == 'accessToken')['value'], 'abc.def');
      expect(vars.firstWhere((v) => v['key'] == 'lang')['value'], '');
    });

    test('the input is not modified', () {
      final pulled = _workspace(collectionAuth: _auth());
      CredentialKeeper.keep(pulled, _workspace(collectionAuth: _auth(value: '{{x}}')));
      expect((pulled['collections'] as List).first['auth']['apiKeyValue'], '');
    });
  });

  group('SecretFields.stripAuth', () {
    test('keeps a {{variable}} reference and drops a literal credential', () {
      final stripped = SecretFields.stripAuth({'type': 'apiKey', 'apiKeyName': 'access-token', 'apiKeyValue': '{{accessToken}}', 'bearerToken': 'eyJhbGciOi.real.token'});
      expect(stripped['apiKeyValue'], '{{accessToken}}');
      expect(stripped.containsKey('bearerToken'), isFalse);
    });
  });
}
