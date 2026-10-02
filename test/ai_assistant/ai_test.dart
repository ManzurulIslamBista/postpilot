import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/ai_assistant/data/ai_client.dart';
import 'package:postpilot/features/ai_assistant/data/ai_settings_store.dart';
import 'package:postpilot/features/ai_assistant/domain/ai_tasks.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';

final class _Store implements AiSettingsStore {
  String? key;
  String modelName = 'claude-test';
  @override
  Future<String?> apiKey() async => key;
  @override
  Future<void> saveApiKey(String k) async => key = k;
  @override
  Future<void> clearApiKey() async => key = null;
  @override
  Future<String> model() async => modelName;
  @override
  Future<void> saveModel(String m) async => modelName = m;
}

final class _Api implements ApiClient {
  ApiRequestSpec? last;
  int status = 200;
  Object body = {'content': [{'type': 'text', 'text': 'hello'}]};
  Object? throwing;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    last = spec;
    if (throwing != null) throw throwing!;
    return ApiHttpResponse(statusCode: status, statusMessage: '', headers: const {}, bodyBytes: utf8.encode(body is String ? body as String : jsonEncode(body)), duration: Duration.zero);
  }
}

void main() {
  group('AiTasks', () {
    test('the explain input masks credentials everywhere and clips huge bodies', () {
      final text = AiTasks.explainInput(
        method: 'POST',
        url: 'https://api.test/x?api_key=SECRETQUERY&q=1',
        statusCode: 401,
        statusText: 'Unauthorized',
        requestHeaders: {'Authorization': 'Bearer abc.def.ghi', 'Accept': 'application/json'},
        requestBody: '{"password":"hunter2","user":"ann"}',
        responseHeaders: {'Set-Cookie': 'sid=XYZ', 'Content-Type': 'application/json'},
        responseBody: '{"token":"tok-999","detail":"${'x' * 20000}"}',
        question: 'Why?',
      );
      for (final secret in ['SECRETQUERY', 'abc.def.ghi', 'hunter2', 'sid=XYZ', 'tok-999']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(text, contains('q=1'));
      expect(text, contains('Accept: application/json'));
      expect(text, contains('QUESTION: Why?'));
      expect(text, contains('more characters'));
      expect(text.length, lessThan(30000));
    });

    test('assertions are read from fenced or chatty replies, and unknown types are dropped', () {
      const reply = 'Sure! Here you go:\n```json\n[{"type":"statusEquals","path":"","expected":"200"},'
          '{"type":"jsonPathExists","path":"data.id","expected":""},{"type":"made_up","path":"x","expected":"y"},'
          '{"type":"jsonSchema","path":"","expected":"{}"}]\n```';
      final a = AiTasks.parseAssertions(reply);
      expect(a.map((x) => x.type), [AssertionType.statusEquals, AssertionType.jsonPathExists]);
      expect(a.first.expected, '200');
      expect(AiTasks.parseAssertions('no json here'), isEmpty);
      expect(AiTasks.parseAssertions('[{"type":"statusIn2xx"}, ${List.filled(12, '{"type":"statusIn2xx"}').join(',')}]'), hasLength(8), reason: 'capped');
    });

    test('a request is read from JSON, with a fence or a sentence around it', () {
      final spec = AiTasks.parseRequest('Here is the request: {"name":"Create customer","method":"post","url":"{{odooUrl}}/json/2/res.partner/create",'
          '"headers":{"Authorization":"bearer {{odooApiKey}}"},"body":{"vals_list":[{"name":"Ann"}]}} Hope it helps')!;
      expect(spec.method, 'POST');
      expect(spec.url, '{{odooUrl}}/json/2/res.partner/create');
      expect(spec.headers['Authorization'], 'bearer {{odooApiKey}}');
      expect(jsonDecode(spec.body!), {'vals_list': [{'name': 'Ann'}]}, reason: 'an object body is written out as JSON text');
      expect(AiTasks.parseRequest('```json\n{"url":"https://a.test"}\n```')!.name, 'GET https://a.test');
    });

    test('unusable replies give null instead of a bad request', () {
      expect(AiTasks.parseRequest('I cannot do that'), isNull);
      expect(AiTasks.parseRequest('{"method":"GET"}'), isNull, reason: 'no URL');
      expect(AiTasks.parseRequest('{"method":"TELEPORT","url":"https://a.test"}'), isNull);
    });
  });

  group('AiClient', () {
    late _Api api;
    late _Store store;
    late AiClient client;

    setUp(() {
      api = _Api();
      store = _Store()..key = 'sk-ant-test';
      client = AiClient(api, store);
    });

    test('sends the key, version, model and prompts in the Messages API shape', () async {
      final text = await client.complete(system: 'be brief', user: 'hi', maxTokens: 50);
      expect(text, 'hello');
      final sent = api.last!;
      expect(sent.url, 'https://api.anthropic.com/v1/messages');
      expect(sent.headers['x-api-key'], 'sk-ant-test');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      final body = jsonDecode(utf8.decode(sent.body as List<int>)) as Map<String, dynamic>;
      expect(body['model'], 'claude-test');
      expect(body['max_tokens'], 50);
      expect(body['system'], 'be brief');
      expect(body['messages'], [{'role': 'user', 'content': 'hi'}]);
    });

    test('joins several text blocks and ignores other kinds', () async {
      api.body = {'content': [{'type': 'text', 'text': 'a'}, {'type': 'tool_use'}, {'type': 'text', 'text': 'b'}]};
      expect(await client.complete(system: 's', user: 'u'), 'a\nb');
    });

    test('explains each kind of failure', () async {
      Future<String> message(int status, [Object? body]) async {
        api
          ..status = status
          ..body = body ?? {'error': {'type': 'x', 'message': 'detail here'}};
        try {
          await client.complete(system: 's', user: 'u');
        } on AiException catch (e) {
          return e.message;
        }
        return 'no error';
      }

      expect(await message(401), contains('API key was rejected'));
      expect(await message(429), contains('Rate limit'));
      expect(await message(529), contains('busy or down'));
      expect(await message(400), contains('detail here'));
      expect(await message(404), contains('not found'));
      expect(await message(200, 'not json at all'), contains('not json at all'), reason: 'an unreadable 200 is an error, not text');
      api.throwing = Exception('offline');
      await expectLater(client.complete(system: 's', user: 'u'), throwsA(isA<AiException>().having((e) => e.message, 'message', contains("Couldn't reach"))));
    });

    test('without a key it asks for one and sends nothing', () async {
      store.key = null;
      expect(await client.hasKey, isFalse);
      await expectLater(client.complete(system: 's', user: 'u'), throwsA(isA<AiException>()));
      expect(api.last, isNull);
    });
  });
}
