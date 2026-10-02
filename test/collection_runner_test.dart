import 'dart:async';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/utils/safe_file_name.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/collections/presentation/view_models/collection_runner_view_model.dart';
import 'package:postpilot/features/collections/presentation/widgets/collection_runner_dialog.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_options.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_report.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/services/run_data_parser.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_result.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/script_run_result.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';

const _collectionId = 1;

void main() {
  group('CollectionRunOptions', () {
    test('makes one pass by default', () {
      expect(const CollectionRunOptions().iterationCount, 1);
    });

    test('limits the iterations to 1..1000', () {
      expect(const CollectionRunOptions(iterations: 0).iterationCount, 1);
      expect(const CollectionRunOptions(iterations: -4).iterationCount, 1);
      expect(const CollectionRunOptions(iterations: 250).iterationCount, 250);
      expect(const CollectionRunOptions(iterations: 5000).iterationCount, CollectionRunOptions.maxIterations);
    });

    test('data rows replace the iteration count and feed one row per pass', () {
      const options = CollectionRunOptions(iterations: 9, dataRows: [
        {'id': '1'},
        {'id': '2'},
      ]);

      expect(options.iterationCount, 2);
      expect(options.dataFor(1), {'id': '1'});
      expect(options.dataFor(2), {'id': '2'});
      expect(const CollectionRunOptions().dataFor(3), isEmpty);
    });
  });

  group('RunDataParser', () {
    const parser = RunDataParser();

    List<Map<String, String>> rowsOf(String text) {
      final data = parser.parse(text);
      expect(data.error, isNull, reason: text);
      return data.rows;
    }

    test('blank text is no data, not an error', () {
      for (final text in ['', '   ', '\n\n']) {
        final data = parser.parse(text);

        expect(data.rows, isEmpty, reason: '"$text"');
        expect(data.error, isNull, reason: '"$text"');
      }
    });

    test('reads CSV with a header row', () {
      final data = parser.parse('id,name\n1,Ada\n2,Grace\n');

      expect(data.columns, ['id', 'name']);
      expect(data.rows, [
        {'id': '1', 'name': 'Ada'},
        {'id': '2', 'name': 'Grace'},
      ]);
    });

    test('trims header cells but keeps values as typed', () {
      final data = parser.parse(' id , name \n 1 , Ada');

      expect(data.columns, ['id', 'name']);
      expect(data.rows.single, {'id': ' 1 ', 'name': ' Ada'});
    });

    test('detects a semicolon, tab or pipe delimiter from the header line', () {
      const expected = [
        {'id': '1', 'name': 'Ada'},
      ];

      expect(rowsOf('id;name\n1;Ada'), expected);
      expect(rowsOf('id\tname\n1\tAda'), expected);
      expect(rowsOf('id|name\n1|Ada'), expected);
    });

    test('honours quotes: delimiters, line breaks and doubled quotes inside a field', () {
      final rows = rowsOf('id,note\n1,"a, b"\n2,"line1\nline2"\n3,"say ""hi"""');

      expect(rows.map((r) => r['note']), ['a, b', 'line1\nline2', 'say "hi"']);
    });

    test('accepts Windows line endings, a BOM and blank lines', () {
      final rows = rowsOf('\u{feff}id,name\r\n1,Ada\r\n\r\n2,Grace\r\n');

      expect(rows, hasLength(2));
      expect(rows.first, {'id': '1', 'name': 'Ada'});
      expect(rows.last['name'], 'Grace');
    });

    test('a short row holds only the cells it has, and an empty cell is an empty string', () {
      final rows = rowsOf('a,b,c\n1,2\n3,,5\n6,7,8,9');

      expect(rows[0], {'a': '1', 'b': '2'});
      expect(rows[1], {'a': '3', 'b': '', 'c': '5'});
      expect(rows[2], {'a': '6', 'b': '7', 'c': '8'});
    });

    test('skips a column whose header is empty', () {
      final data = parser.parse('id,,name\n1,x,Ada');

      expect(data.columns, ['id', 'name']);
      expect(data.rows.single, {'id': '1', 'name': 'Ada'});
    });

    test('reads a JSON array of objects, turning every value into text', () {
      final rows = rowsOf('[{"id":1,"price":9.5,"ok":true,"none":null,"name":"Ada","tags":["a","b"],"meta":{"k":1}}]');

      expect(rows.single, {
        'id': '1',
        'price': '9.5',
        'ok': 'true',
        'none': '',
        'name': 'Ada',
        'tags': '["a","b"]',
        'meta': '{"k":1}',
      });
    });

    test('a lone JSON object is one row', () {
      expect(rowsOf('{"id": 7}'), [
        {'id': '7'},
      ]);
    });

    test('JSON rows may carry different keys, and the columns are their union', () {
      final data = parser.parse('[{"a":"1"},{"b":"2","a":"3"}]');

      expect(data.columns, ['a', 'b']);
      expect(data.rows, [
        {'a': '1'},
        {'b': '2', 'a': '3'},
      ]);
    });

    test('reports invalid JSON', () {
      expect(parser.parse('[{"id":1},').error, startsWith('Invalid JSON'));
      expect(parser.parse('{oops}').error, startsWith('Invalid JSON'));
    });

    test('rejects JSON that is not made of objects', () {
      expect(parser.parse('[1, 2]').error, 'Item 1 of the JSON array is not an object');
      expect(parser.parse('[{"a":1}, "x"]').error, 'Item 2 of the JSON array is not an object');
    });

    test('rejects data with no rows', () {
      expect(parser.parse('[]').error, 'The data has no rows');
      expect(parser.parse('id,name').error, startsWith('CSV needs a header row'));
      expect(parser.parse('id,name\n').error, startsWith('CSV needs a header row'));
    });

    test('rejects a column the {{name}} pattern could never match', () {
      expect(parser.parse('first name,age\nAda,36').error, contains('"first name"'));
      expect(parser.parse('[{"first name":"Ada"}]').error, contains('"first name"'));
    });

    test('accepts the characters a variable name may hold', () {
      expect(parser.parse('user.id,base-url,\$region,snake_case\n1,2,3,4').error, isNull);
    });

    test('rejects a repeated column', () {
      expect(parser.parse('id,id\n1,2').error, 'Column "id" appears more than once');
    });

    test('allows at most as many rows as a run has iterations', () {
      String csvWith(int rows) => ['id', for (var i = 0; i < rows; i++) '$i'].join('\n');

      expect(parser.parse(csvWith(1000)).rows, hasLength(1000));
      expect(parser.parse(csvWith(1001)).error, contains('1001 rows'));
    });
  });

  group('run summary and export', () {
    List<RunIteration> sampleRun() => [
          RunIteration(1, {'id': '1'})
            ..results.addAll([
              CollectionRunResult(
                request: _summary('Get user'),
                response: _response(200, 100),
                scripts: const ScriptRunResult(assertions: [
                  AssertionResult(name: 'Status is 2xx', passed: true, actual: '200'),
                  AssertionResult(name: 'Body contains "id"', passed: true, actual: 'Found in body'),
                ], extracted: []),
              ),
              CollectionRunResult(
                request: _summary('Create, user', method: HttpMethod.post),
                response: _response(500, 300),
                scripts: const ScriptRunResult(assertions: [
                  AssertionResult(name: 'Status equals 201', passed: false, actual: '500'),
                ], extracted: []),
              ),
            ]),
          RunIteration(2, {'id': '2'})
            ..results.add(CollectionRunResult(
              request: _summary('=HYPERLINK("x")'),
              error: 'connection refused',
              iteration: 2,
            )),
        ];

    test('totals the requests, passes, tests and response times', () {
      final summary = CollectionRunSummary.of([for (final iteration in sampleRun()) ...iteration.results]);

      expect(summary.iterations, 2);
      expect(summary.requests, 3);
      expect(summary.passed, 1);
      expect(summary.failed, 2);
      expect(summary.assertions, 3);
      expect(summary.passedAssertions, 2);
      expect(summary.totalTime, const Duration(milliseconds: 400));
      expect(summary.averageTime, const Duration(milliseconds: 200));
    });

    test('an empty run totals to zero without dividing by it', () {
      final summary = CollectionRunSummary.of(const []);

      expect((summary.requests, summary.passed, summary.failed), (0, 0, 0));
      expect(summary.totalTime, Duration.zero);
      expect(summary.averageTime, Duration.zero);
    });

    test('an iteration knows how many of its requests passed', () {
      final iterations = sampleRun();

      expect(iterations.first.passedCount, 1);
      expect(iterations.first.allPassed, isFalse);
    });

    test('a result lists its failed tests and failed variable saves', () {
      const failedSave = ExtractionResult(
        key: 'token',
        scope: ExtractorScope.environment,
        error: 'Not found in response',
      );
      final result = CollectionRunResult(
        request: _summary('Login'),
        response: _response(200, 10),
        scripts: const ScriptRunResult(
          assertions: [AssertionResult(name: 'Status equals 201', passed: false, actual: '200')],
          extracted: [failedSave],
        ),
      );

      expect(result.failures, ['Status equals 201', 'variable token: Not found in response']);
      expect(CollectionRunResult(request: _summary('x'), response: _response(200, 1)).failures, isEmpty);
    });

    test('JSON export carries the summary, each iteration with its data, and every result', () {
      final json = jsonDecode(const CollectionRunExporter().toJson(sampleRun())) as Map<String, dynamic>;

      expect(json['summary'], {
        'iterations': 2,
        'requests': 3,
        'passed': 1,
        'failed': 2,
        'assertions': 3,
        'assertionsPassed': 2,
        'totalTimeMs': 400,
        'averageTimeMs': 200,
      });
      final iterations = json['iterations'] as List;
      expect(iterations.map((i) => (i as Map)['iteration']), [1, 2]);
      expect((iterations.first as Map)['data'], {'id': '1'});
      final results = (iterations.first as Map)['results'] as List;
      expect(results.first, {
        'request': 'Get user',
        'method': 'GET',
        'passed': true,
        'status': 200,
        'timeMs': 100,
        'assertionsPassed': 2,
        'assertionsTotal': 2,
        'failures': <Object>[],
        'error': null,
      });
      expect((results.last as Map)['failures'], ['Status equals 201']);
      final errored = ((iterations.last as Map)['results'] as List).single as Map;
      expect((errored['status'], errored['timeMs'], errored['error']), (null, null, 'connection refused'));
    });

    test('JSON export leaves out the data of a run without any', () {
      final run = [
        RunIteration(1, const {})
          ..results.add(CollectionRunResult(request: _summary('a'), response: _response(200, 5))),
      ];

      final json = jsonDecode(const CollectionRunExporter().toJson(run)) as Map<String, dynamic>;

      expect((json['iterations'] as List).single, isNot(contains('data')));
    });

    test('CSV export has a header, one row per result, quoting and a spreadsheet-formula guard', () {
      final table = Csv(autoDetect: false).decode(const CollectionRunExporter().toCsv(sampleRun()));

      expect(table.first, [
        'iteration', 'request', 'method', 'status', 'timeMs', 'passed', 'assertionsPassed', 'assertionsTotal',
        'failures', 'error',
      ]);
      expect(table, hasLength(4));
      expect(table[1], ['1', 'Get user', 'GET', '200', '100', 'true', '2', '2', '', '']);
      expect(table[2], ['1', 'Create, user', 'POST', '500', '300', 'false', '0', '1', 'Status equals 201', '']);
      expect(table[3][1], '\'=HYPERLINK("x")');
      expect(table[3].sublist(3, 5), ['', '']);
      expect(table[3][9], 'connection refused');
    });

    test('export picks the serializer by format, and the file names are downloadable', () {
      const exporter = CollectionRunExporter();
      final run = sampleRun();

      expect(exporter.export(RunExportFormat.json, run), exporter.toJson(run));
      expect(exporter.export(RunExportFormat.csv, run), exporter.toCsv(run));
      for (final format in RunExportFormat.values) {
        expect(isSafeFileName(format.fileName), isTrue, reason: format.fileName);
      }
      expect((RunExportFormat.json.mimeType, RunExportFormat.csv.mimeType), ('application/json', 'text/csv'));
    });
  });

  group('CollectionRunnerService', () {
    test('sends every request once, in order, by default', () async {
      final harness = _Harness([_request(1, 'https://api.test/a'), _request(2, 'https://api.test/b')]);

      final results = await _runAll(harness);

      expect(results.map((r) => r.request.name), ['Request 1', 'Request 2']);
      expect(results.map((r) => r.iteration), [1, 1]);
      expect(results.every((r) => r.passed), isTrue);
      expect(harness.sentUrls, ['https://api.test/a', 'https://api.test/b']);
    });

    test('repeats the whole collection for each iteration', () async {
      final harness = _Harness([_request(1, 'https://api.test/a'), _request(2, 'https://api.test/b')]);

      final results = await _runAll(harness, options: const CollectionRunOptions(iterations: 3));

      expect(results.map((r) => r.iteration), [1, 1, 2, 2, 3, 3]);
      expect(harness.client.sent, hasLength(6));
    });

    test('data rows set the iteration count and fill their columns into each request', () async {
      final harness = _Harness([
        _request(1, 'https://api.test/users/{{id}}?name={{name}}'),
        _request(2, 'https://api.test/orders/{{id}}'),
      ]);

      final results = await _runAll(
        harness,
        options: const CollectionRunOptions(iterations: 9, dataRows: [
          {'id': '1', 'name': 'Ada'},
          {'id': '2', 'name': 'Grace'},
        ]),
      );

      expect(results.map((r) => r.iteration), [1, 1, 2, 2]);
      expect(harness.sentUrls, [
        'https://api.test/users/1?name=Ada',
        'https://api.test/orders/1',
        'https://api.test/users/2?name=Grace',
        'https://api.test/orders/2',
      ]);
    });

    test('a data column beats a variable of the same name; other tokens still resolve normally', () async {
      final harness = _Harness(
        [_request(1, 'https://{{host}}/users/{{id}}')],
        environment: {'host': 'api.test', 'id': 'from-environment'},
      );

      await _runAll(harness, options: const CollectionRunOptions(dataRows: [
        {'id': '5'},
      ]));

      expect(harness.sentUrls, ['https://api.test/users/5']);
    });

    group('data columns are real variables', () {
      ApiRequestEntity createUser() => ApiRequestEntity(
            id: 1,
            collectionId: _collectionId,
            folderId: null,
            name: 'Create user',
            method: HttpMethod.post,
            url: 'https://{{host}}/users/{{id}}',
            headers: [
              KeyValueItem(key: 'X-Row', value: '{{id}}'),
              KeyValueItem(key: 'X-{{tenant}}', value: 'yes'),
              KeyValueItem(key: 'X-Greeting', value: '{{greeting}}'),
            ],
            queryParams: [KeyValueItem(key: 'page', value: '{{page}}')],
            body: const RequestBody(type: BodyType.raw, rawText: '{"name":"{{name}}"}'),
            auth: const RequestAuth(),
          );

      test("a column reaches the url, query, header names and values, body and the collection's inherited auth",
          () async {
        final harness = _Harness(
          [createUser()],
          environment: {'host': 'api.test', 'greeting': 'hello {{name}}'},
          collectionAuth: const RequestAuth(type: AuthType.bearer, bearerToken: 'tok-{{id}}'),
        );

        await _runAll(harness, options: const CollectionRunOptions(dataRows: [
          {'id': '7', 'name': 'Ada', 'tenant': 'acme', 'page': '2'},
          {'id': '8', 'name': 'Grace', 'tenant': 'globex', 'page': '3'},
        ]));

        final [first, second] = harness.client.sent;
        expect(first.url, 'https://api.test/users/7?page=2');
        expect(first.headers['X-Row'], '7');
        expect(first.headers['X-acme'], 'yes');
        expect(first.headers['Authorization'], 'Bearer tok-7');
        expect(utf8.decode(first.body as List<int>), '{"name":"Ada"}');
        expect(first.headers['X-Greeting'], 'hello Ada', reason: 'an environment value that references a column');
        expect(second.url, 'https://api.test/users/8?page=3');
        expect(second.headers['X-Row'], '8');
        expect(second.headers, isNot(contains('X-acme')), reason: 'a row is used by its own iteration only');
        expect(second.headers['X-globex'], 'yes');
        expect(second.headers['Authorization'], 'Bearer tok-8');
        expect(utf8.decode(second.body as List<int>), '{"name":"Grace"}');
        expect(second.headers['X-Greeting'], 'hello Grace');
      });

      test('a column reaches the assertions and extractors that follow the send, above the environment', () async {
        final harness = _Harness([createUser()], environment: {'host': 'api.test', 'id': 'from-environment'});
        harness.client.bodyFor = (spec) => jsonEncode({
              'echo': {'id': spec.headers['X-Row']},
            });
        harness.scripts.set(
          1,
          [AssertionEntity(type: AssertionType.jsonPathEquals, path: 'echo.id', expected: '{{id}}')],
          extractors: [ExtractorEntity(path: '{{field}}', scope: ExtractorScope.global, variableKey: 'seen')],
        );

        final results = await _runAll(harness, options: const CollectionRunOptions(dataRows: [
          {'id': '7', 'field': 'echo.id'},
          {'id': '8', 'field': 'echo.id'},
        ]));

        expect(results.map((r) => r.failures), [isEmpty, isEmpty]);
        expect(results.map((r) => r.passed), [true, true]);
        expect(results.map((r) => r.passedAssertionCount), [1, 1]);
        expect(results.map((r) => r.scripts!.extracted.single.value), ['7', '8']);
        expect(harness.globals.values, {'seen': '8'});
      });

      test('without a data row the tokens are left to the ordinary scopes', () async {
        final harness = _Harness([createUser()], environment: {'host': 'api.test', 'id': 'from-environment'});

        await _runAll(harness);

        expect(harness.client.sent.single.url, 'https://api.test/users/from-environment?page=%7B%7Bpage%7D%7D');
        expect(harness.client.sent.single.headers['X-Row'], 'from-environment');
        expect(harness.client.sent.single.headers, contains('X-{{tenant}}'));
      });
    });

    test('pauses between requests, across iterations too, but not before the first', () async {
      final harness = _Harness([_request(1, 'https://api.test/a'), _request(2, 'https://api.test/b')]);

      await _runAll(harness, options: const CollectionRunOptions(iterations: 2, delay: Duration(milliseconds: 250)));

      expect(harness.delays, List.filled(3, const Duration(milliseconds: 250)));
    });

    test('never pauses without a delay', () async {
      final harness = _Harness([_request(1, 'https://api.test/a'), _request(2, 'https://api.test/b')]);

      await _runAll(harness, options: const CollectionRunOptions(iterations: 2));

      expect(harness.delays, isEmpty);
    });

    test('stop on first failure ends the whole run at the first request that fails', () async {
      final harness = _Harness([
        _request(1, 'https://api.test/ok'),
        _request(2, 'https://api.test/bad'),
        _request(3, 'https://api.test/ok2'),
      ]);
      harness.client.statusFor = (spec) => spec.url.endsWith('/bad') ? 500 : 200;

      final stopped = await _runAll(harness, options: const CollectionRunOptions(iterations: 2, stopOnFailure: true));
      final unstopped = await _runAll(harness, options: const CollectionRunOptions(iterations: 2));

      expect(stopped.map((r) => r.request.name), ['Request 1', 'Request 2']);
      expect(stopped.last.passed, isFalse);
      expect(unstopped, hasLength(6));
    });

    test('a failed test counts as a failure for stop on first failure, even on HTTP 200', () async {
      final harness = _Harness([_request(1, 'https://api.test/a'), _request(2, 'https://api.test/b')]);
      harness.scripts.set(1, [AssertionEntity(type: AssertionType.statusEquals, expected: '201')]);

      final results = await _runAll(harness, options: const CollectionRunOptions(stopOnFailure: true));

      expect(results, hasLength(1));
      expect(results.single.passed, isFalse);
      expect((results.single.assertionCount, results.single.passedAssertionCount), (1, 0));
      expect(results.single.failures, ['Status equals 201']);
    });

    test('keeps status and timing of a response but not its body', () async {
      final harness = _Harness([_request(1, 'https://api.test/a')]);

      final response = (await _runAll(harness)).single.response!;

      expect(response.statusCode, 200);
      expect(response.duration, const Duration(milliseconds: 40));
      expect(response.bodyBytes, isEmpty);
    });

    test('a request that throws becomes an error result and the run carries on', () async {
      final harness = _Harness([_request(1, 'ftp://api.test/a'), _request(2, 'https://api.test/b')]);

      final results = await _runAll(harness);

      expect(results.first.error, contains('Not a valid http(s) URL'));
      expect(results.first.passed, isFalse);
      expect(results.last.passed, isTrue);
    });

    test('an error result never quotes a secret from the URL, resolved or not', () async {
      final harness = _Harness([
        _request(1, 'ftp://ann:hunter2@api.test/a?api_key=s3cret&page=2'),
        _request(2, '{{baseUrl}}/b?token=t0psecret'),
      ]);

      final results = await _runAll(harness);

      for (final result in results) {
        expect(result.error, contains('Not a valid http(s) URL'));
        expect(result.error, isNot(contains('hunter2')));
        expect(result.error, isNot(contains('s3cret')));
        expect(result.error, isNot(contains('t0psecret')));
      }
      expect(results.first.error, contains('page=2'));
    });

    test('a request deleted mid-run is skipped', () async {
      final harness = _Harness([_request(1, 'https://api.test/a')]);
      final ghost = _summary('Ghost', id: 99);
      final service = CollectionRunnerService(
        _GhostRequestRepository(harness.requests, ghost),
        harness.sendRequest,
        harness.runScripts,
      );

      final results = await service.run(_collectionId).toList();

      expect(results.map((r) => r.request.name), ['Request 1']);
    });

    test('a token cancelled between requests ends the run', () async {
      final harness = _Harness([_request(1, 'https://api.test/a'), _request(2, 'https://api.test/b')]);
      final token = ApiCancelToken();
      final results = <CollectionRunResult>[];

      await for (final result in harness.service.run(_collectionId, cancelToken: token)) {
        results.add(result);
        token.cancel();
      }

      expect(results, hasLength(1));
      expect(harness.client.sent, hasLength(1));
    });

    test('cancelling aborts the request in flight and reports nothing for it', () async {
      final harness = _Harness([_request(1, 'https://api.test/a')]);
      harness.client.gate = Completer<void>();
      final token = ApiCancelToken();

      final results = harness.service.run(_collectionId, cancelToken: token).toList();
      await pumpEventQueue();
      expect(harness.client.sent, hasLength(1));
      token.cancel();

      expect(await results, isEmpty);
    });

    test('cancelling during the pause between requests ends the run', () async {
      final harness = _Harness(
        [_request(1, 'https://api.test/a'), _request(2, 'https://api.test/b')],
        holdDelays: true,
      );
      final token = ApiCancelToken();
      final results = <CollectionRunResult>[];
      final finished = Completer<void>();

      harness.service
          .run(_collectionId, options: const CollectionRunOptions(delay: Duration(seconds: 5)), cancelToken: token)
          .listen(results.add, onDone: finished.complete);
      await pumpEventQueue();
      expect(results, hasLength(1));
      expect(harness.delays, [const Duration(seconds: 5)]);
      token.cancel();
      await finished.future;

      expect(results, hasLength(1));
      expect(harness.client.sent, hasLength(1));
    });

    test('a run that starts with a token already cancelled sends nothing', () async {
      final harness = _Harness([_request(1, 'https://api.test/a')]);
      final token = ApiCancelToken()..cancel();

      expect(await _runAll(harness, cancelToken: token), isEmpty);
      expect(harness.client.sent, isEmpty);
    });
  });

  group('CollectionRunnerViewModel', () {
    _Harness twoRequests() =>
        _Harness([_request(1, 'https://api.test/a', name: 'A'), _request(2, 'https://api.test/b', name: 'B')]);

    test('cannot run before the requests are loaded, or when there are none', () async {
      final vm = _viewModel(twoRequests());

      expect(vm.canRun, isFalse);
      vm.start(_collectionId);
      expect(vm.hasStarted, isFalse);

      await vm.load(_collectionId);
      expect(vm.requests, hasLength(2));
      expect(vm.canRun, isTrue);

      final empty = _viewModel(_Harness(const []));
      await empty.load(_collectionId);
      expect(empty.canRun, isFalse);
      vm.dispose();
      empty.dispose();
    });

    test('iterations must be a whole number from 1 to 1000', () async {
      final vm = _viewModel(twoRequests());
      await vm.load(_collectionId);

      for (final text in ['0', '1001', '', 'abc', '-1', '99999999999999999999']) {
        vm.setIterations(text);
        expect(vm.iterationsError, isNotNull, reason: '"$text"');
        expect(vm.canRun, isFalse, reason: '"$text"');
      }
      for (final text in ['1', '5', ' 1000 ']) {
        vm.setIterations(text);
        expect(vm.iterationsError, isNull, reason: '"$text"');
      }
      vm.setIterations('7');
      expect((vm.plannedIterations, vm.plannedRequestCount), (7, 14));
      vm.dispose();
    });

    test('the delay is optional: whole milliseconds up to ten minutes', () async {
      final vm = _viewModel(twoRequests());
      await vm.load(_collectionId);

      for (final text in ['', '0', '250', ' 600000 ']) {
        vm.setDelayMs(text);
        expect(vm.delayError, isNull, reason: '"$text"');
      }
      for (final text in ['600001', 'abc', '-5', '1.5']) {
        vm.setDelayMs(text);
        expect(vm.delayError, isNotNull, reason: '"$text"');
        expect(vm.canRun, isFalse, reason: '"$text"');
      }
      vm.dispose();
    });

    test('data rows replace the iteration count, and its validation', () async {
      final vm = _viewModel(twoRequests());
      await vm.load(_collectionId);
      vm.setIterations('');
      expect(vm.canRun, isFalse);

      vm.setDataText('id,name\n1,Ada\n2,Grace\n3,Alan');

      expect(vm.usesData, isTrue);
      expect(vm.dataRowCount, 3);
      expect(vm.dataColumns, ['id', 'name']);
      expect(vm.plannedIterations, 3);
      expect(vm.iterationsError, isNull);
      expect(vm.canRun, isTrue);

      vm.setDataText('');
      expect(vm.usesData, isFalse);
      expect(vm.canRun, isFalse);
      vm.dispose();
    });

    test('unusable data blocks the run and says why', () async {
      final vm = _viewModel(twoRequests());
      await vm.load(_collectionId);

      vm.setDataText('[{"id":1},');
      expect(vm.dataError, startsWith('Invalid JSON'));
      expect(vm.canRun, isFalse);

      vm.setDataText('id\n1');
      expect(vm.dataError, isNull);
      expect(vm.canRun, isTrue);
      vm.dispose();
    });

    test('streams results into per-iteration groups with a live summary', () async {
      final vm = _viewModel(twoRequests());
      await vm.load(_collectionId);
      vm.setIterations('2');

      vm.start(_collectionId);
      expect(vm.isRunning, isTrue);
      await _untilIdle(vm);

      expect(vm.results, hasLength(4));
      expect(vm.runIterations.map((i) => i.number), [1, 2]);
      expect(vm.runIterations.map((i) => i.results.length), [2, 2]);
      expect((vm.summary.requests, vm.summary.passed, vm.summary.failed), (4, 4, 0));
      expect(vm.summary.totalTime, const Duration(milliseconds: 160));
      expect(vm.summary.averageTime, const Duration(milliseconds: 40));
      expect(vm.totalIterations, 2);
      expect((vm.wasStopped, vm.stoppedOnFailure, vm.runError), (false, false, null));
      vm.dispose();
    });

    test('a data-driven run gives every iteration its own row', () async {
      final harness = _Harness([_request(1, 'https://api.test/users/{{id}}')]);
      final vm = _viewModel(harness);
      await vm.load(_collectionId);
      vm.setDataText('id\n7\n8\n9');

      vm.start(_collectionId);
      await _untilIdle(vm);

      expect(harness.sentUrls, ['https://api.test/users/7', 'https://api.test/users/8', 'https://api.test/users/9']);
      expect(vm.runIterations.map((i) => i.data), [
        {'id': '7'},
        {'id': '8'},
        {'id': '9'},
      ]);
      expect(vm.totalIterations, 3);
      vm.dispose();
    });

    test('flags a run that ended early on a failure, but not one that failed on its last request', () async {
      final harness = _Harness([
        _request(1, 'https://api.test/ok'),
        _request(2, 'https://api.test/bad'),
        _request(3, 'https://api.test/ok2'),
      ]);
      final vm = _viewModel(harness);
      await vm.load(_collectionId);
      vm.setStopOnFailure(true);

      harness.client.statusFor = (spec) => spec.url.endsWith('/bad') ? 500 : 200;
      vm.start(_collectionId);
      await _untilIdle(vm);
      expect(vm.results.map((r) => r.request.name), ['Request 1', 'Request 2']);
      expect((vm.stoppedOnFailure, vm.wasStopped, vm.summary.failed), (true, false, 1));

      harness.client.statusFor = (spec) => spec.url.endsWith('/ok2') ? 500 : 200;
      vm.start(_collectionId);
      await _untilIdle(vm);
      expect(vm.results, hasLength(3));
      expect(vm.stoppedOnFailure, isFalse);
      vm.dispose();
    });

    test('stop keeps the earlier results, aborts the request in flight, and allows a new run', () async {
      final harness = twoRequests();
      final vm = _viewModel(harness);
      await vm.load(_collectionId);
      void holdSecondRequest() {
        if (vm.results.length == 1 && harness.client.gate == null) harness.client.gate = Completer<void>();
      }

      vm.addListener(holdSecondRequest);

      vm.start(_collectionId);
      await pumpEventQueue();
      expect(vm.results, hasLength(1));
      expect(harness.client.sent, hasLength(2));

      vm.stop();
      expect((vm.isRunning, vm.wasStopped), (false, true));
      await pumpEventQueue();
      expect(vm.results, hasLength(1));
      expect(harness.client.sent, hasLength(2));
      expect(harness.client.sent.last.cancelToken!.isCancelled, isTrue);

      vm.removeListener(holdSecondRequest);
      harness.client.gate = null;
      vm.start(_collectionId);
      await _untilIdle(vm);
      expect(vm.results, hasLength(2));
      expect(vm.wasStopped, isFalse);
      vm.dispose();
    });

    test('closing the dialog mid-run aborts the request in flight', () async {
      final harness = twoRequests();
      harness.client.gate = Completer<void>();
      final vm = _viewModel(harness);
      await vm.load(_collectionId);
      vm.start(_collectionId);
      await pumpEventQueue();

      vm.dispose();
      await pumpEventQueue();

      expect(harness.client.sent.single.cancelToken!.isCancelled, isTrue);
    });

    test('exports what ran as JSON, CSV or a downloaded file', () async {
      String? savedName;
      String? savedMime;
      List<int>? savedBytes;
      final vm = _viewModel(
        twoRequests(),
        download: ({required String fileName, required Uint8List bytes, required String mimeType}) async {
          savedName = fileName;
          savedMime = mimeType;
          savedBytes = bytes;
          return '/downloads/$fileName';
        },
      );
      await vm.load(_collectionId);
      vm.start(_collectionId);
      await _untilIdle(vm);

      final json = jsonDecode(vm.export(RunExportFormat.json)) as Map<String, dynamic>;
      expect((json['summary'] as Map)['requests'], 2);
      expect(vm.export(RunExportFormat.csv).split('\n'), hasLength(3));

      expect(await vm.downloadExport(RunExportFormat.csv), '/downloads/collection-run-results.csv');
      expect((savedName, savedMime), ('collection-run-results.csv', 'text/csv'));
      expect(utf8.decode(savedBytes!), vm.export(RunExportFormat.csv));
      vm.dispose();
    });

    test('starting again clears the previous results', () async {
      final vm = _viewModel(twoRequests());
      await vm.load(_collectionId);

      vm.start(_collectionId);
      await _untilIdle(vm);
      vm.start(_collectionId);
      await _untilIdle(vm);

      expect(vm.results, hasLength(2));
      expect(vm.runIterations, hasLength(1));
      vm.dispose();
    });
  });

  group('CollectionRunnerDialog', () {
    Future<void> openDialog(WidgetTester tester, _Harness harness, {FileDownloader? download}) async {
      final vm = _viewModel(harness, download: download);
      locator.registerFactory<CollectionRunnerViewModel>(() => vm);
      addTearDown(() => locator.reset());

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => CollectionRunnerDialog.show(context, collectionId: _collectionId),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('sets up, runs a data-driven run, shows it per iteration, and exports it', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      String? savedName;
      final harness = _Harness([
        _request(1, 'https://api.test/users/{{id}}', name: 'First'),
        _request(2, 'https://api.test/orders/{{id}}', name: 'Second'),
      ]);

      await openDialog(
        tester,
        harness,
        download: ({required String fileName, required Uint8List bytes, required String mimeType}) async {
          savedName = fileName;
          return 'saved/$fileName';
        },
      );

      expect(find.text('Collection Runner'), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.textContaining('2 requests x 1 iteration: 2 requests will really be sent'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'id\n1\n2');
      await tester.pump();
      expect(find.textContaining('2 rows · id'), findsOneWidget);
      expect(find.textContaining('4 requests will really be sent'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).first).enabled, isFalse);

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('Iteration 1'), findsOneWidget);
      expect(find.text('Iteration 2'), findsOneWidget);
      expect(find.text('Total time'), findsOneWidget);
      expect(find.text('Avg time'), findsOneWidget);
      expect(harness.sentUrls, [
        'https://api.test/users/1',
        'https://api.test/orders/1',
        'https://api.test/users/2',
        'https://api.test/orders/2',
      ]);

      await tester.tap(find.text('Copy JSON'));
      await tester.pump();
      expect(find.text('JSON results copied'), findsOneWidget);
      expect(((jsonDecode(clipboard!) as Map)['summary'] as Map)['requests'], 4);
      ScaffoldMessenger.of(tester.element(find.text('open'))).clearSnackBars();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Download results'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download CSV'));
      await tester.pumpAndSettle();
      expect(savedName, 'collection-run-results.csv');
      expect(find.text('Saved to saved/collection-run-results.csv'), findsOneWidget);

      await tester.tap(find.text('Edit setup'));
      await tester.pumpAndSettle();
      expect(find.text('Iterations'), findsWidgets);
      await tester.tap(find.text('View results'));
      await tester.pumpAndSettle();
      expect(find.text('Iteration 2'), findsOneWidget);
    });

    testWidgets('Stop aborts the run in flight and offers a fresh run', (tester) async {
      final harness = _Harness([_request(1, 'https://api.test/slow', name: 'Slow')]);
      harness.client.gate = Completer<void>();
      await openDialog(tester, harness);

      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Stop'), findsOneWidget);
      expect(harness.client.sent, hasLength(1));

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('Run again'), findsOneWidget);
      expect(harness.client.sent.single.cancelToken!.isCancelled, isTrue);
    });

    testWidgets('shows why the data cannot be used and keeps Run disabled', (tester) async {
      await openDialog(tester, _Harness([_request(1, 'https://api.test/a')]));

      await tester.enterText(find.byType(TextField).last, '[{"id":1},');
      await tester.pump();

      expect(find.textContaining('Invalid JSON'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Run')).onPressed, isNull);
    });
  });
}

RequestSummaryEntity _summary(String name, {int id = 1, HttpMethod method = HttpMethod.get}) =>
    RequestSummaryEntity(id: id, folderId: null, name: name, method: method);

ApiResponseEntity _response(int status, int milliseconds) => ApiResponseEntity(
      statusCode: status,
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: Uint8List(0),
      duration: Duration(milliseconds: milliseconds),
    );

ApiRequestEntity _request(int id, String url, {String? name}) => ApiRequestEntity(
      id: id,
      collectionId: _collectionId,
      folderId: null,
      name: name ?? 'Request $id',
      method: HttpMethod.get,
      url: url,
      headers: const [],
      queryParams: const [],
      body: RequestBody.empty,
      auth: const RequestAuth(type: AuthType.none),
    );

Future<List<CollectionRunResult>> _runAll(
  _Harness harness, {
  CollectionRunOptions options = const CollectionRunOptions(),
  ApiCancelToken? cancelToken,
}) =>
    harness.service.run(_collectionId, options: options, cancelToken: cancelToken).toList();

CollectionRunnerViewModel _viewModel(_Harness harness, {FileDownloader? download}) => CollectionRunnerViewModel(
      harness.service,
      const RunDataParser(),
      const CollectionRunExporter(),
      download ?? ({required String fileName, required Uint8List bytes, required String mimeType}) async => null,
    );

Future<void> _untilIdle(CollectionRunnerViewModel vm) async {
  final idle = Completer<void>();
  void check() {
    if (!vm.isRunning && !idle.isCompleted) idle.complete();
  }

  vm.addListener(check);
  check();
  await idle.future;
  vm.removeListener(check);
}

/// The real send and scripts use cases over fake repositories and a fake HTTP
/// client, so a run is exercised end to end, variable resolution included.
final class _Harness {
  final _FakeApiClient client = _FakeApiClient();
  final _FakeScriptsRepository scripts = _FakeScriptsRepository();
  final _FakeGlobals globals = _FakeGlobals();
  final List<Duration> delays = [];
  final _FakeRequestRepository requests;
  late final SendRequestUseCase sendRequest;
  late final RunRequestScriptsUseCase runScripts;
  late final CollectionRunnerService service;

  _Harness(
    List<ApiRequestEntity> requests, {
    Map<String, String> environment = const {},
    RequestAuth? collectionAuth,
    bool holdDelays = false,
  }) : requests = _FakeRequestRepository(requests) {
    final resolver = BuildVariableResolverUseCase(_NoCollectionVariables(), _FakeEnvironment(environment), globals);
    sendRequest = SendRequestUseCase(client, resolver, _NoHistory(), _FakeCollectionAuth(collectionAuth));
    runScripts = RunRequestScriptsUseCase(scripts, resolver, _FakeEnvironment(environment), globals);
    service = CollectionRunnerService(this.requests, sendRequest, runScripts, (duration) {
      delays.add(duration);
      return holdDelays ? Completer<void>().future : Future<void>.value();
    });
  }

  List<String> get sentUrls => [for (final spec in client.sent) spec.url];
}

final class _FakeRequestRepository implements RequestRepository {
  final List<ApiRequestEntity> requests;
  _FakeRequestRepository(this.requests);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => Stream.value([
        for (final r in requests) RequestSummaryEntity(id: r.id, folderId: r.folderId, name: r.name, method: r.method),
      ]);

  @override
  Future<ApiRequestEntity?> findById(int id) async => requests.where((r) => r.id == id).firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Lists one more request than it can load, as if it was deleted mid-run.
final class _GhostRequestRepository extends _FakeRequestRepository {
  final RequestSummaryEntity ghost;
  _GhostRequestRepository(_FakeRequestRepository real, this.ghost) : super(real.requests);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) =>
      super.watchByCollection(collectionId).map((all) => [ghost, ...all]);
}

final class _FakeApiClient implements ApiClient {
  final List<ApiRequestSpec> sent = [];
  int Function(ApiRequestSpec spec) statusFor = (_) => 200;
  String Function(ApiRequestSpec spec) bodyFor = (_) => '{"ok":true}';

  /// While set, a send waits on it (or on its cancel token) before answering.
  Completer<void>? gate;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add(spec);
    final gate = this.gate;
    if (gate != null) {
      final token = spec.cancelToken;
      await Future.any([gate.future, if (token != null) token.whenCancelled]);
      if (token != null && token.isCancelled) {
        throw const NetworkException('cancelled', kind: NetworkErrorKind.cancelled);
      }
    }
    return ApiHttpResponse(
      statusCode: statusFor(spec),
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: utf8.encode(bodyFor(spec)),
      duration: const Duration(milliseconds: 40),
    );
  }
}

final class _NoHistory implements HistoryRepository {
  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeCollectionAuth implements CollectionAuthRepository {
  final RequestAuth? auth;
  _FakeCollectionAuth(this.auth);

  @override
  Future<String?> getAuthJson(int collectionId) async => auth?.toJsonString();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoCollectionVariables implements CollectionVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap(int collectionId) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeEnvironment implements EnvironmentRepository {
  final Map<String, String> variables;
  _FakeEnvironment(this.variables);

  @override
  Future<Map<String, String>> getActiveVariables() async => variables;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The globals, which the extractors of a run write to.
final class _FakeGlobals implements GlobalVariableRepository {
  final List<GlobalVariableEntity> variables = [];

  Map<String, String> get values => {for (final v in variables.where((v) => v.enabled)) v.key: v.value};

  @override
  Future<Map<String, String>> getEnabledMap() async => values;

  @override
  Stream<List<GlobalVariableEntity>> watchAll() => Stream.value(List.of(variables));

  @override
  Future<void> upsert(GlobalVariableEntity variable) async {
    variables
      ..removeWhere((v) => v.key == variable.key)
      ..add(variable);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeScriptsRepository implements RequestScriptsRepository {
  final Map<int, RequestScriptsEntity> _byRequest = {};

  void set(int requestId, List<AssertionEntity> assertions, {List<ExtractorEntity> extractors = const []}) {
    _byRequest[requestId] = RequestScriptsEntity(
      requestId: requestId,
      assertionsJson: ScriptsJsonCodec.encodeAssertions(assertions),
      extractorsJson: ScriptsJsonCodec.encodeExtractors(extractors),
    );
  }

  @override
  Future<RequestScriptsEntity?> get(int requestId) async => _byRequest[requestId];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
