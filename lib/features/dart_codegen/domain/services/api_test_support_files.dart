/// The files every generated test tree shares: the fixture reader, the JSON matcher and the
/// API client test. They hold no per-collection content, so a project that already has them
/// keeps its own copy (they are written as shared files).
abstract final class ApiTestSupportFiles {
  static const fixtureLoaderPath = 'test/helpers/fixture_loader.dart';
  static const jsonMatchersPath = 'test/helpers/json_matchers.dart';
  static const apiClientTestPath = 'test/core/network/api_client_test.dart';

  static const fixtureLoader = r'''// Reads the JSON fixtures the generated tests are built from (test/fixtures).
//
// Run the tests from the project root (`flutter test` does), because the fixtures are found
// relative to it.
import 'dart:convert';
import 'dart:io';

/// The decoded JSON of `test/fixtures/<name>`.
Object? loadJsonFixture(String name) => jsonDecode(loadTextFixture(name));

/// A fixture whose root is a JSON object.
Map<String, dynamic> loadJsonObjectFixture(String name) => loadJsonFixture(name) as Map<String, dynamic>;

/// A fixture whose root is a JSON array.
List<dynamic> loadJsonListFixture(String name) => loadJsonFixture(name) as List<dynamic>;

/// The raw text of `test/fixtures/<name>` (an answer that is not JSON).
String loadTextFixture(String name) {
  final file = File('test/fixtures/$name');
  if (!file.existsSync()) {
    throw StateError('The fixture test/fixtures/$name does not exist. Run the tests from the project root.');
  }
  return file.readAsStringSync();
}
''';

  /// The matcher the model and data source tests compare JSON with. [frameworkImport] is the
  /// import line of the test package the project uses.
  static String jsonMatchers(String frameworkImport) => '''// Compares JSON the way the models read it, for the generated tests.
//
// * A key that is absent and a key that is null are the same thing: a model cannot tell them apart.
// * Numbers compare by value (`1` and `1.0` are equal).
// * Two ISO-8601 dates compare by the moment they name: `DateTime.toIso8601String` adds
//   milliseconds and a `Z`, so the text of a date does not survive a round trip.
$frameworkImport

/// Matches a decoded JSON value that says the same as [expected].
Matcher jsonEquivalentTo(Object? expected) => _JsonEquivalent(expected);

class _JsonEquivalent extends Matcher {
  const _JsonEquivalent(this._expected);

  final Object? _expected;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    final problem = _difference(_expected, item, r'\$');
    if (problem == null) return true;
    matchState['problem'] = problem;
    return false;
  }

  @override
  Description describe(Description description) => description.add('the same JSON as the saved example');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) =>
      mismatchDescription.add(matchState['problem'] as String? ?? 'is different');
}

final _isoDate = RegExp(r'^\\d{4}-\\d{2}-\\d{2}([T ]\\d{2}:\\d{2}(:\\d{2}(\\.\\d+)?)?(Z|[+-]\\d{2}:?\\d{2})?)?\$');

DateTime? _asDate(String text) => _isoDate.hasMatch(text) ? DateTime.tryParse(text) : null;

String _show(Object? value) => value is String ? '"\$value"' : '\$value';

/// What differs between [expected] and [actual] at [path], or null when they say the same.
String? _difference(Object? expected, Object? actual, String path) {
  if (expected is Map && actual is Map) {
    for (final key in {...expected.keys, ...actual.keys}) {
      final inExpected = expected[key];
      final inActual = actual[key];
      if (inExpected == null && inActual == null) continue;
      final problem = _difference(inExpected, inActual, '\$path.\$key');
      if (problem != null) return problem;
    }
    return null;
  }
  if (expected is List && actual is List) {
    if (expected.length != actual.length) return '\$path has \${actual.length} items, expected \${expected.length}';
    for (var i = 0; i < expected.length; i++) {
      final problem = _difference(expected[i], actual[i], '\$path[\$i]');
      if (problem != null) return problem;
    }
    return null;
  }
  if (expected is num && actual is num) {
    return expected == actual ? null : '\$path is \$actual, expected \$expected';
  }
  if (expected is String && actual is String && expected != actual) {
    final expectedDate = _asDate(expected);
    final actualDate = _asDate(actual);
    if (expectedDate != null && actualDate != null && expectedDate.isAtSameMomentAs(actualDate)) return null;
  }
  return expected == actual ? null : '\$path is \${_show(actual)}, expected \${_show(expected)}';
}
''';

  /// The test of the generated `createApiClient`: base URL, the bearer token and the JSON
  /// `Accept` header, with a Dio adapter that records what would have been sent.
  static String apiClientTest(String packageName, String frameworkImport) => '''// Tests of lib/core/network/api_client.dart as PostPilot generated it. If you replaced that file
// with your own client, adjust or delete this test.
import 'dart:typed_data';

import 'package:dio/dio.dart';
$frameworkImport
import 'package:$packageName/core/network/api_client.dart';

/// Answers every call with `{}` and keeps what it was asked.
class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('uses the base URL it is given', () {
    final dio = createApiClient(baseUrl: 'https://api.test');
    expect(dio.options.baseUrl, 'https://api.test');
  });

  test('asks for JSON', () async {
    final adapter = _RecordingAdapter();
    final dio = createApiClient(baseUrl: 'https://api.test')..httpClientAdapter = adapter;
    await dio.get<dynamic>('/ping');
    expect(adapter.requests.single.headers['Accept'], 'application/json');
  });

  test('sends the bearer token the provider returns', () async {
    final adapter = _RecordingAdapter();
    final dio = createApiClient(baseUrl: 'https://api.test', tokenProvider: () async => 'test-token')
      ..httpClientAdapter = adapter;
    await dio.get<dynamic>('/ping');
    expect(adapter.requests.single.headers['Authorization'], 'Bearer test-token');
  });

  test('asks the provider again for every call', () async {
    final adapter = _RecordingAdapter();
    var calls = 0;
    final dio = createApiClient(baseUrl: 'https://api.test', tokenProvider: () async => 'token-\${++calls}')
      ..httpClientAdapter = adapter;
    await dio.get<dynamic>('/a');
    await dio.get<dynamic>('/b');
    expect(adapter.requests.map((r) => r.headers['Authorization']), ['Bearer token-1', 'Bearer token-2']);
  });

  test('sends no Authorization header when the provider has no token', () async {
    final adapter = _RecordingAdapter();
    final dio = createApiClient(baseUrl: 'https://api.test', tokenProvider: () async => null)..httpClientAdapter = adapter;
    await dio.get<dynamic>('/ping');
    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('sends no Authorization header without a token provider', () async {
    final adapter = _RecordingAdapter();
    final dio = createApiClient(baseUrl: 'https://api.test')..httpClientAdapter = adapter;
    await dio.get<dynamic>('/ping');
    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });
}
''';
}
