// The generated test tree, for every model style and both test packages: each file must parse. For the plain
// style it must also COMPILE with the generated API layer: the layer and its tests are written into a
// throw-away package and type-checked with the analyzer against the dio, mocktail and test packages
// that are in this machine's pub cache (see generated_package_check.dart). Nothing here uses the network.
//
// What this does not prove, and says so: `http_mock_adapter` is not in the pub cache, so the data source
// tests are checked against a permissive stand-in for that one package. Everything around its calls
// (imports, generated names, argument names and types, DTO construction) is type-checked; whether the
// real package accepts those calls is not. The json_serializable and freezed styles need build_runner's
// part files, so they are checked for syntax only. No generated test is executed here.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_layer_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_test_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';
import 'generated_package_check.dart';
import 'shop_api_fixture.dart';

/// Accepts any call a generated data source test makes on the adapter, so the rest of the file can be
/// type-checked. It says nothing about the real package's API.
const _httpMockAdapterStandIn = '''
// Permissive stand-in for http_mock_adapter, used only to type-check generated tests offline.
class DioAdapter {
  DioAdapter({Object? dio});
  void onGet(String path, Object? handler, {Object? data, Map<String, dynamic>? queryParameters, Object? headers}) {}
  void onPost(String path, Object? handler, {Object? data, Map<String, dynamic>? queryParameters, Object? headers}) {}
  void onPut(String path, Object? handler, {Object? data, Map<String, dynamic>? queryParameters, Object? headers}) {}
  void onPatch(String path, Object? handler, {Object? data, Map<String, dynamic>? queryParameters, Object? headers}) {}
  void onDelete(String path, Object? handler, {Object? data, Map<String, dynamic>? queryParameters, Object? headers}) {}
}
''';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('postpilot_api_tests_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  for (final style in DartModelStyle.values) {
    for (final framework in TestFramework.values) {
      for (final nullable in [false, true]) {
        test('every generated file parses (${style.name}, ${framework.name}, all optional: $nullable)', () {
          final layer = ApiLayerOptions(packageName: 'shop_app', modelStyle: style, allNullable: nullable);
          final tests = const ApiTestGenerator().generate('Shop API', shopApiRequests(), options: ApiTestOptions(layer: layer, framework: framework));
          final api = const ApiLayerGenerator().generate('Shop API', shopApiRequests(), options: layer);
          expect(tests.files.map((f) => f.path).toSet(), hasLength(tests.files.length), reason: 'no file is generated twice');
          for (final f in [...api.files, ...tests.files]) {
            if (!f.path.endsWith('.dart')) continue;
            final parsed = parseString(content: f.content, path: f.path, throwIfDiagnostics: false);
            expect(parsed.errors, isEmpty, reason: '${f.path}: ${parsed.errors.map((e) => e.message).join('; ')}');
          }
        });
      }
    }
  }

  test('the generated API layer and its generated tests compile together (plain models, package:test)', () async {
    const layer = ApiLayerOptions(packageName: 'shop_app');
    final api = const ApiLayerGenerator().generate('Shop API', shopApiRequests(), options: layer);
    final tests = const ApiTestGenerator().generate(
      'Shop API',
      shopApiRequests(),
      options: const ApiTestOptions(layer: layer, framework: TestFramework.dartTest),
    );
    final files = {
      for (final f in [...api.files, ...tests.files]) f.path: f.content,
    };
    final check = await checkGeneratedPackage(
      root: dir,
      packageName: 'shop_app',
      files: files,
      // get_it is imported by the generated injection file.
      directDependencies: const ['dio', 'get_it', 'mocktail', 'test', 'http_mock_adapter'],
      standIns: const {'http_mock_adapter': _httpMockAdapterStandIn},
      lintPaths: const {'test/'},
    );
    if (check.skippedBecause != null) {
      markTestSkipped('Not compiled: ${check.skippedBecause}.');
      return;
    }
    expect(check.problems, isEmpty, reason: 'resolved ${check.resolved}\n${check.problems.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
