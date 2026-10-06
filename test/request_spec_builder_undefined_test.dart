import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/services/undefined_variables.dart';

ApiRequestEntity _request({
  String url = 'https://api.example.com/items',
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> params = const [],
  RequestBody body = RequestBody.empty,
  RequestAuth auth = const RequestAuth(type: AuthType.none),
}) =>
    ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: 'r',
      method: HttpMethod.post,
      url: url,
      headers: headers,
      queryParams: params,
      body: body,
      auth: auth,
    );

KeyValueItem _kv(String key, String value, {bool enabled = true}) =>
    KeyValueItem(key: key, value: value, enabled: enabled);

/// Name -> where it is used, for the variables nothing in [defined] holds.
Map<String, List<String>> _undefined(
  ApiRequestEntity request, {
  Map<String, String> defined = const {},
  RequestAuth? inheritedAuth,
  bool trim = false,
}) =>
    {
      for (final v in const RequestSpecBuilder().undefinedVariables(
        request,
        VariableResolver(defined),
        inheritedAuth: inheritedAuth,
        trimKeysAndValues: trim,
      ))
        v.name: v.places,
    };

void main() {
  group('VariableResolver.undefinedIn', () {
    final resolver = VariableResolver({'host': 'api.test', 'empty': '', 'self': '{{self}}', 'url': '{{host}}/{{gone}}'});

    test('names only what no scope holds, in order of first appearance, once each', () {
      expect(resolver.undefinedIn('{{b}} {{host}} {{a}} {{b}}'), ['b', 'a']);
    });

    test('a variable defined with an empty value is defined', () {
      expect(resolver.undefinedIn('{{empty}}'), isEmpty);
    });

    test(r'a built-in {{$guid}} is defined, an unknown {{$name}} is not', () {
      expect(resolver.undefinedIn(r'{{$guid}} {{$timestamp}} {{$randomInt}}'), isEmpty);
      expect(resolver.undefinedIn(r'{{$notABuiltIn}}'), [r'$notABuiltIn']);
    });

    test('a variable that references itself stays literal on purpose and counts as defined', () {
      expect(resolver.undefinedIn('{{self}}'), isEmpty);
      expect(resolver.resolve('{{self}}'), '{{self}}');
    });

    test('finds the undefined name inside the value of a defined variable', () {
      expect(resolver.undefinedIn('{{url}}'), ['gone']);
    });

    test('is a pure look: it resolves nothing and layers like resolve does', () {
      const layered = VariableResolver.layered([
        {'a': '1'},
        {'b': '2'},
      ]);

      expect(layered.undefinedIn('{{a}}{{b}}{{c}}'), ['c']);
      expect(layered.resolve('{{a}}{{b}}{{c}}'), '12{{c}}');
    });
  });

  group('RequestSpecBuilder.undefinedVariables', () {
    test('a request whose variables are all defined has none', () {
      final request = _request(
        url: '{{baseUrl}}/items',
        headers: [_kv('X-Token', '{{token}}')],
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
      );

      expect(_undefined(request, defined: {'baseUrl': 'https://a.test', 'token': 't'}), isEmpty);
    });

    test('a variable defined with an empty value is not undefined', () {
      expect(_undefined(_request(url: 'https://a.test/{{suffix}}'), defined: {'suffix': ''}), isEmpty);
    });

    test('names every one, with where it is used', () {
      final request = _request(
        url: '{{baseUrl}}/users/{{id}}',
        params: [_kv('page', '{{page}}')],
        headers: [_kv('X-Tenant', '{{tenant}}')],
        body: const RequestBody(type: BodyType.raw, rawText: '{"name":"{{name}}"}'),
      );

      expect(_undefined(request), {
        'baseUrl': ['the URL'],
        'id': ['the URL'],
        'page': ['the query parameter "page"'],
        'tenant': ['the "X-Tenant" header'],
        'name': ['the request body'],
      });
    });

    test('lists each place a variable is used in', () {
      final request = _request(url: 'https://a.test/{{v}}', headers: [_kv('X-V', '{{v}}')]);

      expect(_undefined(request)['v'], ['the URL', 'the "X-V" header']);
    });

    test('a built-in dynamic variable is never undefined', () {
      final request = _request(
        url: r'https://a.test/{{$guid}}',
        headers: [_kv('X-Time', r'{{$timestamp}}')],
        body: const RequestBody(type: BodyType.raw, rawText: r'{"id":"{{$randomUUID}}"}'),
      );

      expect(_undefined(request), isEmpty);
    });

    test('rows that are switched off, or whose key ends up empty, are not sent and not checked', () {
      final request = _request(
        headers: [_kv('X-Off', '{{off}}', enabled: false), _kv('{{blankKey}}', '{{dropped}}')],
        params: [_kv('', '{{noKey}}')],
      );

      expect(_undefined(request, defined: {'blankKey': ''}), isEmpty);
    });

    test('keys count as well as values, and trimming is mirrored', () {
      final request = _request(headers: [_kv('X-{{tenant}}', 'v')]);

      expect(_undefined(request), {'tenant': ['the "X-{{tenant}}" header']});
      expect(_undefined(_request(headers: [_kv('  ', '{{x}}')]), trim: true), isEmpty);
    });

    test('form fields, GraphQL parts and the auth of the type in force are read', () {
      final form = _request(
        body: RequestBody(type: BodyType.urlEncoded, urlEncodedFields: [_kv('user', '{{u}}')]),
      );
      final multipart = _request(
        body: RequestBody(type: BodyType.formData, formFields: [_kv('file', '{{f}}')]),
      );
      final graphql = _request(
        body: const RequestBody(type: BodyType.graphql, graphqlQuery: '{ a(id: "{{q}}") }', graphqlVariables: '{"v":"{{gv}}"}'),
      );

      expect(_undefined(form), {'u': ['the form field "user"']});
      expect(_undefined(multipart), {'f': ['the form field "file"']});
      expect(_undefined(graphql), {'q': ['the GraphQL query'], 'gv': ['the GraphQL variables']});
    });

    test('only the body of the type in use counts, and only the auth of the type in use', () {
      final request = _request(
        body: RequestBody(type: BodyType.none, rawText: '{{unusedBody}}', urlEncodedFields: [_kv('a', '{{unusedForm}}')]),
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'x', basicPassword: '{{unusedAuth}}'),
      );

      expect(_undefined(request), isEmpty);
    });

    test('auth: every field of each type is checked, an inherited auth when the request inherits', () {
      final basic = _request(auth: const RequestAuth(type: AuthType.basic, basicUsername: '{{u}}', basicPassword: '{{p}}'));
      final apiKey = _request(
        auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'k', apiKeyValue: '{{key}}'),
      );
      final aws = _request(
        auth: const RequestAuth(type: AuthType.awsSignatureV4, awsAccessKey: '{{ak}}', awsSecretKey: '{{sk}}'),
      );
      final inherits = _request(auth: const RequestAuth(type: AuthType.inherit));

      expect(_undefined(basic), {'u': ['the Basic auth user name'], 'p': ['the Basic auth password']});
      expect(_undefined(apiKey), {'key': ['the API key']});
      expect(_undefined(aws).keys, containsAll(['ak', 'sk']));
      expect(
        _undefined(inherits, inheritedAuth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{inheritedToken}}')),
        {'inheritedToken': ['the Bearer token']},
      );
    });

    test('an API key with no name sends nothing, so its value is not checked', () {
      final request = _request(auth: const RequestAuth(type: AuthType.apiKey, apiKeyValue: '{{key}}'));

      expect(_undefined(request), isEmpty);
    });

    test('build itself still produces the request, with the token left in it', () {
      final spec = const RequestSpecBuilder().build(_request(url: '{{baseUrl}}/items'), const VariableResolver.layered([]));

      expect(spec.url, contains('{{baseUrl}}'));
    });
  });

  group('UndefinedVariables.exception', () {
    InvalidRequestException error(Map<String, List<String>> found, {String url = 'https://api.test/x', Set<String> body = const {}}) =>
        UndefinedVariables.exception([for (final e in found.entries) UndefinedVariable(e.key, e.value, inBody: body.contains(e.key))], url);

    test('one variable: names it, where it is used, and what to do', () {
      final message = error({'token': ['the "Authorization" header']}).message;

      expect(message, startsWith('{{token}} (used in the "Authorization" header) is not defined.'));
      expect(message, contains('Select an environment'));
    });

    test('several variables are all named, with their places', () {
      final message = error({
        'a': ['the URL', 'the "X" header'],
        'b': ['the request body'],
      }).message;

      expect(message, contains('{{a}} (used in the URL and the "X" header)'));
      expect(message, contains('{{b}} (used in the request body)'));
      expect(message, startsWith('These variables are not defined:'));
    });

    test('a placeholder in the host is not a URL: the URL is quoted, its secrets masked', () {
      final message = error({'baseUrl': ['the URL']}, url: 'http://{{baseUrl}}/b?token=t0psecret').message;

      expect(message, startsWith('Not a valid http(s) URL: "http://{{baseUrl}}/b?token='));
      expect(message, isNot(contains('t0psecret')));
    });

    test('a placeholder further along the URL does not make it an invalid URL', () {
      final message = error({'id': ['the URL']}, url: 'https://api.test/users/{{id}}').message;

      expect(message, isNot(contains('Not a valid')));
    });

    test('a variable of the body comes with the way to send it as plain text', () {
      final message = error({'name': ['the request body']}, body: {'name'}).message;

      expect(message, contains('define a variable named name whose value is {{name}}'));
      expect(error({'name': ['the URL']}).message, isNot(contains('plain text')));
    });
  });
}
