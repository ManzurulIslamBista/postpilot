import 'dart:convert';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../entities/generated_file.dart';
import 'api_layer_generator.dart';
import 'api_test_support_files.dart';
import 'dart_model_generator.dart';
import 'dart_names.dart';

/// Which test package the generated tests import.
enum TestFramework {
  flutterTest('Flutter (flutter_test)', "import 'package:flutter_test/flutter_test.dart';"),
  dartTest('Dart (package:test)', "import 'package:test/test.dart';");

  const TestFramework(this.label, this.importLine);

  final String label;
  final String importLine;
}

final class ApiTestOptions {
  /// How the API layer under test is generated: the tests are built from the same plan.
  final ApiLayerOptions layer;
  final TestFramework framework;

  /// Package name to resolved version, from the project's `pubspec.lock` (see `PubspecLockVersions`).
  final Map<String, String> lockedVersions;

  const ApiTestOptions({
    this.layer = const ApiLayerOptions(),
    this.framework = TestFramework.flutterTest,
    this.lockedVersions = const {},
  });
}

final class ApiTestsResult {
  final List<GeneratedFile> files;
  final List<String> notes;

  /// A `dev_dependencies:` block with what the tests import.
  final String devDependencies;

  /// The command that adds those packages at their current version.
  final String addCommand;

  const ApiTestsResult({required this.files, required this.notes, required this.devDependencies, required this.addCommand});
}

/// Generates the `test/` tree for a generated API layer: fixtures from the saved examples (secrets
/// masked), a round-trip test for every model, a data source test per group on `http_mock_adapter`,
/// and repository and use case tests on `mocktail`.
///
/// It builds on [ApiLayerGenerator.plan], so the names, signatures and DTOs the tests use are the
/// ones the API layer was generated with. What it asserts matches what that layer does: the
/// repository hands the data source's DTO on unchanged (there is no separate entity), and neither the
/// repository nor the use case catches anything, so a failure reaches the caller as it is.
final class ApiTestGenerator {
  const ApiTestGenerator();

  /// Versions that exist on pub.dev: both are in the pub cache this was written against (mocktail 1.0.4 and
  /// 1.0.5, test 1.25.8 up to 1.31.1). `http_mock_adapter` has no entry because no version of it could be
  /// confirmed here, so it is left to `pub add`.
  static const fallbackVersions = {'mocktail': '^1.0.4', 'test': '^1.25.8'};

  ApiTestsResult generate(String collectionName, List<ApiSpecRequest> requests, {ApiTestOptions options = const ApiTestOptions()}) {
    if (requests.isEmpty) {
      return const ApiTestsResult(files: [], notes: ['The collection has no requests.'], devDependencies: '', addCommand: '');
    }
    final plan = const ApiLayerGenerator().plan(collectionName, requests, options: options.layer);
    return _Run(plan, options).build();
  }
}

/// The state of one generation, so the emitters do not pass it around.
final class _Run {
  _Run(this.plan, this.options)
      : pkg = plan.packageName,
        feature = plan.feature,
        style = plan.options.modelStyle,
        framework = options.framework.importLine;

  final ApiLayerPlan plan;
  final ApiTestOptions options;
  final String pkg;
  final String feature;
  final DartModelStyle style;
  final String framework;

  final _notes = <String>[];

  /// Fixture path (below `test/fixtures`) to its text.
  final _fixtures = <String, String>{};
  final _modelFixtures = <String, String>{};
  final _untestable = <String>[];

  bool get _domain => plan.options.domainLayer;

  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  ApiTestsResult build() {
    final files = <GeneratedFile>[
      GeneratedFile(ApiTestSupportFiles.fixtureLoaderPath, ApiTestSupportFiles.fixtureLoader, shared: true),
      GeneratedFile(ApiTestSupportFiles.jsonMatchersPath, ApiTestSupportFiles.jsonMatchers(framework), shared: true),
      GeneratedFile(ApiTestSupportFiles.apiClientTestPath, ApiTestSupportFiles.apiClientTest(pkg, framework), shared: true),
    ];

    // Every model is the root of one saved example (or request body), so each gets one test file.
    final listRoots = <String>{
      for (final ops in plan.groups.values)
        for (final op in ops)
          if (op.responseIsList && op.responseModel != null) op.responseModel!.path,
    };
    for (final model in plan.models.values) {
      final path = 'test/features/$feature/data/models/${DartNames.snake(model.root)}_test.dart';
      files.add(GeneratedFile(path, _modelTest(model, listRoots.contains(model.path), path)));
    }

    plan.groups.forEach((group, ops) {
      final snake = DartNames.snake(group);
      final dsPath = 'test/features/$feature/data/datasources/${snake}_remote_data_source_test.dart';
      final ds = _dataSourceTest(group, ops, dsPath);
      if (ds != null) files.add(GeneratedFile(dsPath, ds));
      if (_domain) {
        final repoPath = 'test/features/$feature/data/repositories/${snake}_repository_impl_test.dart';
        files.add(GeneratedFile(repoPath, _repositoryTest(group, ops, snake, repoPath)));
        final ucPath = 'test/features/$feature/domain/usecases/${snake}_usecases_test.dart';
        files.add(GeneratedFile(ucPath, _useCaseTest(group, ops, snake, ucPath)));
      }
    });

    final fixturePaths = _fixtures.keys.toList()..sort();
    for (final name in fixturePaths) {
      files.add(GeneratedFile('test/fixtures/$name', _fixtures[name]!));
    }

    return ApiTestsResult(
      files: files,
      notes: _finishNotes(),
      devDependencies: _devDependencies(),
      addCommand: _addCommand(),
    );
  }

  // --- notes and dependencies ------------------------------------------------------

  List<String> _finishNotes() {
    final notes = <String>[..._notes];
    if (style != DartModelStyle.plain) {
      notes.add('The models use ${style.label}: run `dart run build_runner build` before the tests, so the generated '
          '.g.dart${style == DartModelStyle.freezed ? ' and .freezed.dart' : ''} files exist.');
    }
    if (_untestable.isNotEmpty) {
      final more = _untestable.length > 3 ? ' and ${_untestable.length - 3} more' : '';
      notes.add('No data source test for ${_untestable.take(3).join(', ')}$more: http_mock_adapter cannot match a multipart '
          'form or a GraphQL body, and has no helper for HEAD, OPTIONS or custom methods. Their repository and use case tests are generated.');
    }
    notes.add('The data source tests call createApiClient from lib/core/network/api_client.dart as generated: if you replaced '
        'that file, adjust the setUp. Fields that look like enums are String in the models, so there is no enum to test.');
    notes.add('Run the tests from the project root (`${options.framework == TestFramework.dartTest ? 'dart test' : 'flutter test'}`): '
        'the fixtures are read from test/fixtures.');
    return notes;
  }

  String? _constraint(String name) {
    final locked = options.lockedVersions[name];
    if (locked != null) return '^$locked';
    return ApiTestGenerator.fallbackVersions[name];
  }

  String _devDependencies() {
    final b = StringBuffer('dev_dependencies:\n');
    if (options.framework == TestFramework.flutterTest) {
      b
        ..writeln('  flutter_test:')
        ..writeln('    sdk: flutter');
    } else {
      b.writeln('  test: ${_constraint('test')}');
    }
    b.writeln('  mocktail: ${_constraint('mocktail')}');
    final adapter = _constraint('http_mock_adapter');
    if (adapter != null) {
      b.writeln('  http_mock_adapter: $adapter');
    } else {
      b
        ..writeln('  # http_mock_adapter: add it at its current version with the command below,')
        ..writeln('  # no version of it could be confirmed when these tests were generated.');
    }
    return b.toString();
  }

  String _addCommand() {
    final tool = options.framework == TestFramework.dartTest ? 'dart' : 'flutter';
    final missing = [
      if (options.framework == TestFramework.dartTest && !options.lockedVersions.containsKey('test')) 'test',
      if (!options.lockedVersions.containsKey('mocktail')) 'mocktail',
      if (!options.lockedVersions.containsKey('http_mock_adapter')) 'http_mock_adapter',
    ];
    return missing.isEmpty ? '' : '$tool pub add --dev ${missing.join(' ')}';
  }

  // --- fixtures ------------------------------------------------------------------------

  /// A name for a fixture below `test/fixtures` that no other fixture has.
  String _fixtureName(String wanted) {
    var name = '$feature/$wanted';
    final dot = wanted.lastIndexOf('.');
    final stem = wanted.substring(0, dot);
    final extension = wanted.substring(dot);
    var n = 2;
    while (_fixtures.containsKey(name)) {
      name = '$feature/$stem$n$extension';
      n++;
    }
    return name;
  }

  /// Credentials in a saved example are masked, wherever they are in it: the fixtures are committed with the tests.
  /// Dates and `{{variable}}` references keep their values, so the fixture still parses.
  Object? _masked(Object? node, [String? key]) {
    switch (node) {
      case Map<dynamic, dynamic>():
        return {for (final e in node.entries) '${e.key}': _masked(e.value, '${e.key}')};
      case List<dynamic>():
        return [for (final item in node) _masked(item, key)];
      case String():
        if (key == null || _isoDate.hasMatch(node)) return node;
        return SecretMasker.maskValue(key, node);
      case num():
        if (key != null && SecretNames.isNumericSecretKey(key)) return node is int ? 0 : 0.0;
        return node;
      default:
        return node;
    }
  }

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$');

  Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// The same text asked for under the same name is one fixture, however many tests use it.
  final _registered = <String, String?>{};

  /// Registers the JSON fixture for [text] and returns its name. Null when [text] is not JSON.
  String? _jsonFixture(String wanted, String text) => _registered.putIfAbsent('$wanted\u0000$text', () {
        final decoded = _tryJson(text.trim());
        if (decoded == null && text.trim() != 'null') return null;
        final name = _fixtureName(wanted);
        _fixtures[name] = '${_jsonEncoder.convert(_masked(decoded))}\n';
        return name;
      });

  String _textFixture(String wanted, String text) => _registered.putIfAbsent('$wanted\u0000$text', () {
        final name = _fixtureName(wanted);
        _fixtures[name] = '${SecretMasker.maskBody(text)}\n';
        return name;
      })!;

  Object? _decodedFixture(String name) => jsonDecode(_fixtures[name]!);

  /// The fixture of a model's saved example (registered on first use).
  String _fixtureOf(ApiModel model) =>
      _modelFixtures.putIfAbsent(model.path, () => _jsonFixture('${DartNames.snake(model.root)}.json', model.sample)!);

  // --- shared pieces -----------------------------------------------------------------------

  String _quote(String value) => DartNames.quote(value);

  /// `../` steps from the folder of [from] up to `test/`.
  String _toTest(String from) {
    final depth = from.split('/').length - 2;
    return List.filled(depth, '..').join('/');
  }

  /// The import lines for [body]: only what it uses, so the file has no unused import.
  String _header(String comment, String path, String body, {required List<String> packages, List<ApiModel> models = const []}) {
    final b = StringBuffer('// $comment\n');
    final dart = <String>[
      if (body.contains('jsonDecode(') || body.contains('jsonEncode(')) "import 'dart:convert';",
    ];
    // A DTO is imported only when the test names it: an inferred type needs no import.
    final modelLines = {
      for (final m in models)
        if (RegExp('\\b${m.root}\\b').hasMatch(body)) "import 'package:$pkg/${m.libPath}';",
    };
    final relative = <String>[
      if (body.contains('loadJson') || body.contains('loadText')) "import '${_toTest(path)}/helpers/fixture_loader.dart';",
      if (body.contains('jsonEquivalentTo(')) "import '${_toTest(path)}/helpers/json_matchers.dart';",
    ];
    final packageLines = {...packages, framework, ...modelLines}.toList()..sort();
    if (dart.isNotEmpty) b.writeln(dart.join('\n'));
    if (dart.isNotEmpty) b.writeln();
    b.writeln(packageLines.join('\n'));
    if (relative.isNotEmpty) {
      b
        ..writeln()
        ..writeln(relative.join('\n'));
    }
    b
      ..writeln()
      ..write(body);
    return b.toString();
  }

  List<ApiModel> _modelsOf(List<ApiOperation> ops) => [
        for (final op in ops) ...[?op.requestModel, ?op.responseModel],
      ];

  // --- model tests ---------------------------------------------------------------------------

  String _modelTest(ApiModel model, bool isList, String path) {
    final cls = model.rootClass;
    final fixture = _fixtureOf(model);
    final decoded = _decodedFixture(fixture);
    final item = (isList ? (decoded as List).first : decoded) as Map<dynamic, dynamic>;
    final root = model.root;

    final tests = <String>[];

    // 1. What the saved example says, field by field.
    final expectations = _expectations(model, cls, item, 'model', 0, _Budget(40));
    tests.add([
      "    test('reads the saved example', () {",
      '      final model = $root.fromJson(item());',
      for (final line in expectations) '      $line',
      if (expectations.isEmpty) '      expect(model, isNotNull);',
      '    });',
    ].join('\n'));

    // 2. The way back. Going through jsonEncode is what an app does, and it is what makes nested classes
    // (json_serializable leaves them as objects in toJson) and dates comparable.
    tests.add([
      "    test('writes the same JSON back', () {",
      if (isList) ...[
        '      final models = fixture().map((e) => $root.fromJson(e as Map<String, dynamic>)).toList();',
        '      expect(jsonDecode(jsonEncode(models)), jsonEquivalentTo(fixture()));',
      ] else ...[
        '      final model = $root.fromJson(item());',
        '      expect(jsonDecode(jsonEncode(model)), jsonEquivalentTo(item()));',
      ],
      '    });',
    ].join('\n'));

    // 3. Optional fields.
    final optional = [for (final f in cls.fields) if (f.nullable) f];
    if (optional.isNotEmpty) {
      final keys = optional.map((f) => _quote(f.json)).join(', ');
      tests.add([
        "    test('reads an object that leaves out its optional fields', () {",
        '      final json = <String, dynamic>{...item()}..removeWhere((key, _) => const {$keys}.contains(key));',
        '      final model = $root.fromJson(json);',
        for (final f in optional) '      expect(model.${f.name}, isNull);',
        '    });',
      ].join('\n'));
    }

    // 4. What the chosen style adds.
    if (style == DartModelStyle.freezed) {
      tests
        ..add([
          "    test('two instances read from the same JSON are equal (freezed value equality)', () {",
          '      expect($root.fromJson(item()), $root.fromJson(item()));',
          '      expect($root.fromJson(item()).hashCode, $root.fromJson(item()).hashCode);',
          '    });',
        ].join('\n'))
        ..add([
          "    test('copyWith with no arguments keeps every value', () {",
          '      final model = $root.fromJson(item());',
          '      expect(model.copyWith(), model);',
          '    });',
        ].join('\n'));
    } else if (style == DartModelStyle.plain && plan.options.allNullable && cls.fields.isNotEmpty) {
      tests.add([
        "    test('copyWith with no arguments keeps every value', () {",
        '      final model = $root.fromJson(item());',
        '      expect(jsonDecode(jsonEncode(model.copyWith())), jsonEquivalentTo(jsonDecode(jsonEncode(model))));',
        '    });',
      ].join('\n'));
    }

    final body = [
      'void main() {',
      '  group(${_quote(root)}, () {',
      if (isList) ...[
        '    List<dynamic> fixture() => loadJsonListFixture(${_quote(fixture)});',
        '    Map<String, dynamic> item() => fixture().first as Map<String, dynamic>;',
      ] else
        '    Map<String, dynamic> item() => loadJsonObjectFixture(${_quote(fixture)});',
      '',
      tests.join('\n\n'),
      '  });',
      '}',
      '',
    ].join('\n');
    final hint = style == DartModelStyle.plain
        ? 'Round-trip test of $root against test/fixtures/$fixture.'
        : 'Round-trip test of $root against test/fixtures/$fixture. Needs the ${style.label} part files (run build_runner).';
    return _header(hint, path, body, packages: ["import 'package:$pkg/${model.libPath}';"]);
  }

  /// `expect` lines for the fields of [cls], read from the saved [json]. [access] is the Dart expression for the object.
  List<String> _expectations(ApiModel model, DartClassInfo cls, Map<dynamic, dynamic> json, String access, int depth, _Budget budget) {
    final lines = <String>[];
    for (final f in cls.fields) {
      if (budget.left <= 0) break;
      if (f.kind == DartFieldKind.dynamicType) continue;
      final value = json[f.json];
      final field = '$access.${f.name}';
      if (value == null) {
        if (f.nullable) lines.add('expect($field, isNull);');
        budget.left--;
        continue;
      }
      switch (f.kind) {
        case DartFieldKind.string when value is String:
          lines.add('expect($field, ${_quote(value)});');
        case DartFieldKind.integer when value is num:
          lines.add('expect($field, $value);');
        case DartFieldKind.decimal when value is num:
          lines.add('expect($field, closeTo($value, 1e-9));');
        case DartFieldKind.boolean when value is bool:
          lines.add('expect($field, $value);');
        case DartFieldKind.date when value is String:
          lines.add('expect($field, DateTime.parse(${_quote(value)}));');
        case DartFieldKind.list when value is List:
          lines.add('expect($field, hasLength(${value.length}));');
          final items = _scalarItems(f, value);
          if (items != null) lines.add('expect($field, $items);');
          if (f.itemKind == DartFieldKind.object && !f.itemNullable && value.isNotEmpty && value.first is Map && depth < 2) {
            final itemClass = model.result.classes.where((c) => c.name == f.itemTypeName).firstOrNull;
            if (itemClass != null) {
              final first = f.nullable ? '$field![0]' : '$field[0]';
              budget.left--;
              lines.addAll(_expectations(model, itemClass, value.first as Map, first, depth + 1, budget));
              continue;
            }
          }
        case DartFieldKind.object when value is Map:
          final nested = model.result.classes.where((c) => c.name == f.typeName).firstOrNull;
          if (f.nullable) lines.add('expect($field, isNotNull);');
          if (nested != null && depth < 2) {
            budget.left--;
            lines.addAll(_expectations(model, nested, value, f.nullable ? '$field!' : field, depth + 1, budget));
            continue;
          }
          if (!f.nullable) lines.add('expect($field, isNotNull);');
        case DartFieldKind.map when value is Map:
          lines.add('expect($field, hasLength(${value.length}));');
        default:
          continue;
      }
      budget.left--;
    }
    return lines;
  }

  /// The items of a short list of strings or integers as a Dart list literal; null for anything else.
  String? _scalarItems(DartFieldInfo f, List<dynamic> value) {
    if (value.isEmpty || value.length > 5 || f.itemNullable) return null;
    if (f.itemKind == DartFieldKind.string && value.every((e) => e is String)) return '[${value.map((e) => _quote(e as String)).join(', ')}]';
    if (f.itemKind == DartFieldKind.integer && value.every((e) => e is int)) return '[${value.join(', ')}]';
    return null;
  }

  // --- arguments of a call ---------------------------------------------------------------------

  String _sampleValue(ApiParam p) => 'test-${DartNames.words(p.name).join('-')}';
  /// The arguments a test passes to [op]: [all] of them, or only those the call cannot do without. An optional
  /// argument left out that has a default still appears, not passed, with the value the default gives the request.
  List<_Arg> _args(ApiOperation op, {required bool all}) {
    final args = <_Arg>[];
    for (final p in op.params) {
      if (!all && !p.required) {
        if (p.defaultValue != null) args.add(_Arg(p, value: p.defaultValue, expr: _quote(p.defaultValue!), passed: false));
        continue;
      }
      if (p.kind != ApiParamKind.body) {
        final value = _sampleValue(p);
        args.add(_Arg(p, value: value, expr: _quote(value)));
        continue;
      }
      args.add(_bodyArg(op, p));
    }
    return args;
  }
  /// The body argument: a request DTO read from its fixture, a decoded JSON fixture, or a small literal.
  _Arg _bodyArg(ApiOperation op, ApiParam p) {
    final name = p.name;
    final model = op.requestModel;
    if (model != null) {
      return _Arg(
        p,
        expr: name,
        decl: "final $name = ${model.root}.fromJson(loadJsonObjectFixture(${_quote(_fixtureOf(model))}));",
        data: '$name.toJson()',
      );
    }
    switch (op.bodyKind) {
      case ApiBodyKind.json:
        final decoded = op.bodyJson;
        if (decoded is Map || decoded is List) {
          final fixture = _jsonFixture('${DartNames.snake(op.group)}_${DartNames.snake(op.methodName)}_request.json', jsonEncode(decoded));
          if (fixture != null) {
            final loader = decoded is List ? 'loadJsonListFixture' : 'loadJsonObjectFixture';
            return _Arg(p, expr: name, decl: 'final $name = $loader(${_quote(fixture)});', data: name);
          }
        }
        return _Arg(p, expr: name, decl: 'final $name = <String, dynamic>{};', data: name);
      case ApiBodyKind.text:
        return _Arg(p, value: 'test body', expr: "'test body'", data: "'test body'");
      case ApiBodyKind.graphql:
        return _Arg(p, expr: name, decl: "final $name = <String, dynamic>{'id': 1};", data: name);
      case ApiBodyKind.urlEncoded || ApiBodyKind.form || ApiBodyKind.none:
        return _Arg(p, expr: name, decl: "final $name = <String, dynamic>{'field': 'value'};", data: name);
    }
  }

  String _callArgs(List<_Arg> args) => [for (final a in args) if (a.passed) '${a.param.name}: ${a.expr}'].join(', ');

  /// What a call with [args] asks of the server: path, query, headers.
  ({String path, Map<String, String> query, Map<String, String> headers}) _expectedRequest(ApiOperation op, List<_Arg> args) {
    final values = <String, String>{
      for (final a in args)
        if (a.value != null) a.param.name: a.value!,
    };
    final path = ApiTextPart.evaluate(op.pathParts, values);
    final query = <String, String>{};
    for (final q in op.queryEntries) {
      if (q.onlyIfSet != null && !values.containsKey(q.onlyIfSet)) continue;
      query[q.key] = ApiTextPart.evaluate(q.parts, values);
    }
    final headers = <String, String>{
      for (final h in op.headerEntries)
        // The interceptor of the generated client sets Authorization last, whatever the call passed.
        if (h.key.toLowerCase() != 'authorization') h.key: ApiTextPart.evaluate(h.parts, values),
    };
    return (path: path, query: query, headers: headers);
  }

  String _stringMap(Map<String, String> map) =>
      '<String, dynamic>{${map.entries.map((e) => '${_quote(e.key)}: ${_quote(e.value)}').join(', ')}}';

  // --- data source tests ------------------------------------------------------------------------

  static const _mockableMethods = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'};

  bool _mockable(ApiOperation op) =>
      _mockableMethods.contains(op.httpMethod) && op.bodyKind != ApiBodyKind.form && op.bodyKind != ApiBodyKind.graphql;

  String? _dataSourceTest(String group, List<ApiOperation> ops, String path) {
    final testable = ops.where(_mockable).toList();
    for (final op in ops) {
      if (!_mockable(op)) _untestable.add(op.title);
    }
    if (testable.isEmpty) return null;

    final snake = DartNames.snake(group);
    final b = StringBuffer()
      ..writeln('void main() {')
      ..writeln('  late Dio dio;')
      ..writeln('  late DioAdapter adapter;')
      ..writeln('  late ${group}RemoteDataSource dataSource;')
      ..writeln('  late List<RequestOptions> sent;')
      ..writeln()
      ..writeln('  setUp(() {')
      ..writeln('    sent = [];')
      ..writeln('    // An empty base URL keeps the mocked paths exactly as the data source writes them.')
      ..writeln("    dio = createApiClient(baseUrl: '', tokenProvider: () async => 'test-token');")
      ..writeln('    adapter = DioAdapter(dio: dio);')
      ..writeln('    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {')
      ..writeln('      sent.add(options);')
      ..writeln('      handler.next(options);')
      ..writeln('    }));')
      ..writeln('    dataSource = ${group}RemoteDataSource(dio);')
      ..writeln('  });')
      ..writeln()
      ..writeln('  group(${_quote('${group}RemoteDataSource')}, () {');
    for (var i = 0; i < testable.length; i++) {
      if (i > 0) b.writeln();
      b.write(_dataSourceOp(testable[i]));
    }
    b
      ..writeln('  });')
      ..writeln('}');
    return _header(
      'Tests of ${group}RemoteDataSource: Dio on http_mock_adapter, answers from the saved examples in test/fixtures.',
      path,
      b.toString(),
      packages: [
        "import 'package:dio/dio.dart';",
        "import 'package:http_mock_adapter/http_mock_adapter.dart';",
        "import 'package:$pkg/core/network/api_client.dart';",
        "import 'package:$pkg/features/$feature/data/datasources/${snake}_remote_data_source.dart';",
      ],
      models: _modelsOf(ops),
    );
  }

  String _dataSourceOp(ApiOperation op) {
    final method = 'on${DartNames.pascal(op.httpMethod.toLowerCase())}';
    final success = _successReply(op);
    final full = _args(op, all: true);
    final expected = _expectedRequest(op, full);
    final bodyData = full.where((a) => a.data != null).map((a) => a.data!).firstOrNull;
    final label = '${op.title}: ${op.httpMethod} ${op.docPath}';

    String register(String indent, _Reply reply, Map<String, String> query, String? data) {
      final b = StringBuffer()
        ..writeln('${indent}adapter.$method(')
        ..writeln('$indent  ${_quote(expected.path)},')
        ..writeln('$indent  (server) => server.reply(${reply.status}, ${reply.data}),');
      if (data != null) b.writeln('$indent  data: $data,');
      if (query.isNotEmpty) b.writeln('$indent  queryParameters: ${_stringMap(query)},');
      b.writeln('$indent);');
      return b.toString();
    }

    String decls(String indent, List<_Arg> args) =>
        [for (final a in args) if (a.passed && a.decl != null) '$indent${a.decl}\n'].join();

    final b = StringBuffer()..writeln('    group(${_quote(op.methodName)}, () {');

    // Success: the request that goes out and the DTO that comes back.
    b
      ..writeln('      test(${_quote('$label sends the request and parses the saved example')}, () async {')
      ..write(decls('        ', full))
      ..write(register('        ', success.reply, expected.query, bodyData))
      ..writeln()
      ..writeln('        final result = await dataSource.${op.methodName}(${_callArgs(full)});')
      ..writeln();
    for (final line in success.assertions) {
      b.writeln('        $line');
    }
    b
      ..writeln('        expect(sent, hasLength(1));')
      ..writeln("        expect(sent.single.method, ${_quote(op.httpMethod)});")
      ..writeln('        expect(sent.single.path, ${_quote(expected.path)});');
    if (expected.query.isEmpty) {
      b.writeln('        expect(sent.single.queryParameters, isEmpty);');
    } else {
      b.writeln('        expect(sent.single.queryParameters, ${_stringMap(expected.query)});');
    }
    for (final h in expected.headers.entries) {
      b.writeln('        expect(sent.single.headers[${_quote(h.key)}], ${_quote(h.value)});');
    }
    b
      ..writeln("        expect(sent.single.headers['Authorization'], 'Bearer test-token');")
      ..writeln('      });');

    // Optional query parameters: defaults applied, unset ones left out.
    if (op.params.any((p) => !p.required && p.kind == ApiParamKind.query)) {
      final minimal = _args(op, all: false);
      final min = _expectedRequest(op, minimal);
      final minData = minimal.where((a) => a.data != null).map((a) => a.data!).firstOrNull;
      b
        ..writeln()
        ..writeln('      test(${_quote('$label applies the defaults and leaves out the optional query parameters it was not given')}, () async {')
        ..write(decls('        ', minimal))
        ..write(register('        ', success.reply, min.query, minData))
        ..writeln()
        ..writeln('        await dataSource.${op.methodName}(${_callArgs(minimal)});')
        ..writeln()
        ..writeln('        expect(sent.single.path, ${_quote(min.path)});');
      if (min.query.isEmpty) {
        b.writeln('        expect(sent.single.queryParameters, isEmpty);');
      } else {
        b.writeln('        expect(sent.single.queryParameters, ${_stringMap(min.query)});');
      }
      b.writeln('      });');
    }

    // Failures: every status the collection has an example for, else a plain 500.
    for (final failure in _failureReplies(op)) {
      b
        ..writeln()
        ..writeln('      test(${_quote('$label fails with a DioException on a ${failure.status} answer${failure.name.isEmpty ? '' : ' (${failure.name})'}')}, () async {')
        ..write(decls('        ', full))
        ..write(register('        ', failure.reply, expected.query, bodyData))
        ..writeln()
        ..writeln('        await expectLater(')
        ..writeln('          dataSource.${op.methodName}(${_callArgs(full)}),')
        ..writeln("          throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', ${failure.status})),")
        ..writeln('        );')
        ..writeln('      });');
    }
    b.writeln('    });');
    return b.toString();
  }

  /// The reply for a successful call and the assertions on what the call returned.
  ({_Reply reply, List<String> assertions}) _successReply(ApiOperation op) {
    final source = op.source;
    final example = source.exampleResponse?.trim() ?? '';
    final status = source.examples.where((e) => e.isSuccess && e.body.trim() == example && example.isNotEmpty).firstOrNull?.statusCode ?? 200;
    final model = op.responseModel;
    if (model != null) {
      final fixture = _fixtureOf(model);
      final loader = op.responseIsList ? 'loadJsonListFixture' : 'loadJsonObjectFixture';
      return (
        reply: _Reply(status, 'loadJsonFixture(${_quote(fixture)})'),
        assertions: ['expect(jsonDecode(jsonEncode(result)), jsonEquivalentTo($loader(${_quote(fixture)})));'],
      );
    }
    if (example.isNotEmpty) {
      final wanted = '${DartNames.snake(op.group)}_${DartNames.snake(op.methodName)}_response';
      final json = _jsonFixture('$wanted.json', example);
      if (json != null) {
        return (
          reply: _Reply(status, 'loadJsonFixture(${_quote(json)})'),
          assertions: ['expect(result, jsonEquivalentTo(loadJsonFixture(${_quote(json)})));'],
        );
      }
      final text = _textFixture('$wanted.txt', example);
      return (reply: _Reply(status, 'loadTextFixture(${_quote(text)})'), assertions: ['expect(result, isNotNull);']);
    }
    return (
      reply: _Reply(status, "<String, dynamic>{'ok': true}"),
      assertions: ["expect(result, <String, dynamic>{'ok': true});"],
    );
  }

  /// One reply per distinct error status among the saved examples (three at most).
  List<({int status, String name, _Reply reply})> _failureReplies(ApiOperation op) {
    final seen = <int>{};
    final replies = <({int status, String name, _Reply reply})>[];
    for (final e in op.source.examples) {
      if (e.isSuccess || e.statusCode < 400 || !seen.add(e.statusCode)) continue;
      if (replies.length == 3) break;
      final wanted = '${DartNames.snake(op.group)}_${DartNames.snake(op.methodName)}_${e.statusCode}';
      final body = e.body.trim();
      String data;
      if (body.isEmpty) {
        data = "''";
      } else {
        final json = _jsonFixture('$wanted.json', body);
        data = json != null ? 'loadJsonFixture(${_quote(json)})' : 'loadTextFixture(${_quote(_textFixture('$wanted.txt', body))})';
      }
      replies.add((status: e.statusCode, name: e.name, reply: _Reply(e.statusCode, data)));
    }
    if (replies.isEmpty) {
      replies.add((status: 500, name: '', reply: const _Reply(500, "<String, dynamic>{'message': 'Internal Server Error'}")));
    }
    return replies;
  }

  // --- repository and use case tests ---------------------------------------------------------------

  /// A Dart expression for a value of the operation's return type, built from its fixture.
  String _sampleResult(ApiOperation op) {
    final model = op.responseModel;
    if (model != null) {
      final fixture = _quote(_fixtureOf(model));
      if (op.responseIsList) {
        return 'loadJsonListFixture($fixture).map((e) => ${model.root}.fromJson(e as Map<String, dynamic>)).toList()';
      }
      return '${model.root}.fromJson(loadJsonObjectFixture($fixture))';
    }
    final example = op.source.exampleResponse?.trim() ?? '';
    if (example.isNotEmpty && op.responseType == 'List<dynamic>') {
      final json = _jsonFixture('${DartNames.snake(op.group)}_${DartNames.snake(op.methodName)}_response.json', example);
      if (json != null) return 'loadJsonListFixture(${_quote(json)})';
    }
    return "<String, dynamic>{'ok': true}";
  }

  String _repositoryTest(String group, List<ApiOperation> ops, String snake, String path) {
    final b = StringBuffer()
      ..writeln('class _Mock${group}RemoteDataSource extends Mock implements ${group}RemoteDataSource {}')
      ..writeln()
      ..writeln('void main() {')
      ..writeln('  late _Mock${group}RemoteDataSource remote;')
      ..writeln('  late ${group}RepositoryImpl repository;')
      ..writeln()
      ..writeln('  setUp(() {')
      ..writeln('    remote = _Mock${group}RemoteDataSource();')
      ..writeln('    repository = ${group}RepositoryImpl(remote);')
      ..writeln('  });');
    for (final op in ops) {
      final args = _args(op, all: true);
      final call = _callArgs(args);
      final declLines = [for (final a in args) if (a.passed && a.decl != null) '      ${a.decl}\n'].join();
      b
        ..writeln()
        ..writeln('  group(${_quote(op.methodName)}, () {')
        ..writeln("    test('returns what the data source returns, unchanged', () async {")
        ..write(declLines)
        ..writeln('      final sample = ${_sampleResult(op)};')
        ..writeln('      when(() => remote.${op.methodName}($call)).thenAnswer((_) async => sample);')
        ..writeln()
        ..writeln('      final result = await repository.${op.methodName}($call);')
        ..writeln()
        ..writeln('      expect(result, same(sample));')
        ..writeln('      verify(() => remote.${op.methodName}($call)).called(1);')
        ..writeln('    });')
        ..writeln()
        ..writeln("    test('lets a failure of the data source reach the caller as it is', () async {")
        ..write(declLines)
        ..writeln("      final error = DioException(requestOptions: RequestOptions(path: ${_quote(_expectedRequest(op, args).path)}), type: DioExceptionType.badResponse);")
        ..writeln('      when(() => remote.${op.methodName}($call)).thenAnswer((_) => Future<${op.responseType}>.error(error));')
        ..writeln()
        ..writeln('      await expectLater(repository.${op.methodName}($call), throwsA(same(error)));')
        ..writeln('      verify(() => remote.${op.methodName}($call)).called(1);')
        ..writeln('    });')
        ..writeln('  });');
    }
    b.writeln('}');
    return _header(
      'Tests of ${group}RepositoryImpl on mocktail. The repository forwards each call to the data source and hands its '
      'answer on unchanged; it catches nothing, so a failure reaches the caller as it is.',
      path,
      b.toString(),
      packages: [
        "import 'package:dio/dio.dart';",
        "import 'package:mocktail/mocktail.dart';",
        "import 'package:$pkg/features/$feature/data/datasources/${snake}_remote_data_source.dart';",
        "import 'package:$pkg/features/$feature/data/repositories/${snake}_repository_impl.dart';",
      ],
      models: _modelsOf(ops),
    );
  }

  String _useCaseTest(String group, List<ApiOperation> ops, String snake, String path) {
    final b = StringBuffer()
      ..writeln('class _Mock${group}Repository extends Mock implements ${group}Repository {}')
      ..writeln()
      ..writeln('void main() {')
      ..writeln('  late _Mock${group}Repository repository;')
      ..writeln()
      ..writeln('  setUp(() => repository = _Mock${group}Repository());');
    for (final op in ops) {
      final args = _args(op, all: true);
      final call = _callArgs(args);
      final declLines = [for (final a in args) if (a.passed && a.decl != null) '      ${a.decl}\n'].join();
      final noParams = op.params.isEmpty;
      final canBeConst = noParams || args.every((a) => a.decl == null);
      final params = noParams ? 'const NoParams()' : '${canBeConst ? 'const ' : ''}${op.useCaseParamsName}($call)';
      b
        ..writeln()
        ..writeln('  group(${_quote(op.useCaseName)}, () {')
        ..writeln("    test('asks the repository with the parameters it was given and returns its answer', () async {")
        ..write(declLines)
        ..writeln('      final sample = ${_sampleResult(op)};')
        ..writeln('      when(() => repository.${op.methodName}($call)).thenAnswer((_) async => sample);')
        ..writeln()
        ..writeln('      final result = await ${op.useCaseName}(repository)($params);')
        ..writeln()
        ..writeln('      expect(result, same(sample));')
        ..writeln('      verify(() => repository.${op.methodName}($call)).called(1);')
        ..writeln('    });')
        ..writeln()
        ..writeln("    test('passes a failure of the repository on unchanged', () async {")
        ..write(declLines)
        ..writeln("      final error = DioException(requestOptions: RequestOptions(path: ${_quote(_expectedRequest(op, args).path)}), type: DioExceptionType.badResponse);")
        ..writeln('      when(() => repository.${op.methodName}($call)).thenAnswer((_) => Future<${op.responseType}>.error(error));')
        ..writeln()
        ..writeln('      await expectLater(${op.useCaseName}(repository)($params), throwsA(same(error)));')
        ..writeln('    });')
        ..writeln('  });');
    }
    b.writeln('}');
    return _header(
      'Tests of the $group use cases on mocktail. Each one calls its repository method with the fields of its parameters '
      'and returns the answer; nothing is caught on the way.',
      path,
      b.toString(),
      packages: [
        "import 'package:dio/dio.dart';",
        "import 'package:mocktail/mocktail.dart';",
        if (ops.any((op) => op.params.isEmpty)) "import 'package:$pkg/core/usecases/usecase.dart';",
        "import 'package:$pkg/features/$feature/domain/repositories/${snake}_repository.dart';",
        for (final op in ops) "import 'package:$pkg/features/$feature/domain/usecases/${op.useCaseFile}';",
      ],
      models: _modelsOf(ops),
    );
  }
}

/// How many `expect` lines a model test may hold: a model with sixty fields is not asserted line by line.
final class _Budget {
  _Budget(this.left);
  int left;
}

/// One argument of a call in a generated test.
final class _Arg {
  final ApiParam param;

  /// The text the argument adds to the request (a path segment, a query value); null for a body.
  final String? value;

  /// The Dart expression that passes it.
  final String expr;

  /// A declaration the test needs first (a DTO read from its fixture).
  final String? decl;

  /// False for an optional argument the test leaves out; it is listed only for the value its default gives the request.
  final bool passed;

  /// What the request carries as `data`; null when the argument is not the body.
  final String? data;

  const _Arg(this.param, {this.value, required this.expr, this.decl, this.data, this.passed = true});
}

/// What a mocked route answers: a status and a Dart expression for the data.
final class _Reply {
  final int status;
  final String data;
  const _Reply(this.status, this.data);
}
