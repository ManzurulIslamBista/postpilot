import 'dart:convert';
import '../entities/generated_file.dart';
import 'dart_model_generator.dart';
import 'dart_names.dart';

enum ApiBodyKind { none, json, text, form, urlEncoded, graphql }

/// A request reduced to what code generation needs, so the generator knows
/// nothing about the database or the UI.
final class ApiSpecRequest {
  final String name;
  final String method;
  final String url;
  final List<(String, String)> query;
  final List<(String, String)> headers;
  final ApiBodyKind bodyKind;
  final String bodyText;

  /// A saved response example (JSON text); gives the response DTO its shape.
  final String? exampleResponse;

  /// Folder names from the collection root to this request.
  final List<String> folders;

  const ApiSpecRequest({
    required this.name,
    required this.method,
    required this.url,
    this.query = const [],
    this.headers = const [],
    this.bodyKind = ApiBodyKind.none,
    this.bodyText = '',
    this.exampleResponse,
    this.folders = const [],
  });
}

final class ApiLayerOptions {
  final String packageName;
  final DartModelStyle modelStyle;

  /// Add repository + use case classes on top of the data source.
  final bool domainLayer;

  /// Make every DTO field nullable and optional (see [DartModelOptions.allNullable]).
  final bool allNullable;

  const ApiLayerOptions({
    this.packageName = 'app',
    this.modelStyle = DartModelStyle.plain,
    this.domainLayer = true,
    this.allNullable = false,
  });
}

final class ApiLayerResult {
  final List<GeneratedFile> files;
  final List<String> notes;
  const ApiLayerResult(this.files, this.notes);
}

/// Generates a feature-first Dart API layer from a collection: a Dio data
/// source with one method per request, request/response DTOs inferred from
/// bodies and saved examples, and (optionally) the repository and use cases
/// the rest of the app calls. `{{variables}}` and `:params` in a URL become
/// typed method parameters.
final class ApiLayerGenerator {
  const ApiLayerGenerator();

  static final _variable = RegExp(r'\{\{\s*([^{}\s]+)\s*\}\}');

  ApiLayerResult generate(String collectionName, List<ApiSpecRequest> requests, {ApiLayerOptions options = const ApiLayerOptions()}) {
    final notes = <String>[];
    final feature = DartNames.snake(collectionName, fallback: 'api');
    final pkg = options.packageName;
    final files = <GeneratedFile>[];
    if (requests.isEmpty) return const ApiLayerResult([], ['The collection has no requests.']);

    final base = _commonBase(requests);
    files.add(GeneratedFile('lib/core/network/api_client.dart', _apiClient(base)));
    if (options.domainLayer) files.add(const GeneratedFile('lib/core/usecases/usecase.dart', _useCaseBase));

    // One data source / repository per top-level folder; loose requests share one named after the collection.
    final groups = <String, List<_Operation>>{};
    final usedMethodNames = <String, Set<String>>{};
    final modelFiles = <String, GeneratedFile>{};
    for (final request in requests) {
      final groupName = request.folders.isEmpty ? collectionName : request.folders.first;
      final group = DartNames.pascal(groupName, fallback: 'Api');
      final taken = usedMethodNames.putIfAbsent(group, () => <String>{});
      final op = _operation(request, taken, options, modelFiles, feature, notes);
      groups.putIfAbsent(group, () => []).add(op);
    }

    for (final file in modelFiles.values) {
      files.add(file);
    }

    List<String> modelImports(List<_Operation> ops) =>
        {for (final op in ops) ...op.modelImports}.map((p) => "import 'package:$pkg/$p';").toList()..sort();

    final registrations = <String>[];
    groups.forEach((group, ops) {
      final snake = DartNames.snake(group);
      final dsPath = 'lib/features/$feature/data/datasources/${snake}_remote_data_source.dart';
      files.add(GeneratedFile(dsPath, _dataSource(group, ops, modelImports(ops), pkg)));
      registrations.add('    ..registerLazySingleton<${group}RemoteDataSource>(() => ${group}RemoteDataSource(sl<Dio>()))');
      if (options.domainLayer) {
        files
          ..add(GeneratedFile('lib/features/$feature/domain/repositories/${snake}_repository.dart', _repositoryInterface(group, ops, modelImports(ops), pkg)))
          ..add(GeneratedFile('lib/features/$feature/data/repositories/${snake}_repository_impl.dart', _repositoryImpl(group, ops, feature, snake, modelImports(ops), pkg)));
        registrations
            .add('    ..registerLazySingleton<${group}Repository>(() => ${group}RepositoryImpl(sl<${group}RemoteDataSource>()))');
        for (final op in ops) {
          files.add(GeneratedFile('lib/features/$feature/domain/usecases/${DartNames.snake(op.methodName)}_usecase.dart',
              _useCase(group, op, feature, snake, modelImports(ops), pkg)));
          registrations.add('    ..registerLazySingleton<${op.useCaseName}>(() => ${op.useCaseName}(sl<${group}Repository>()))');
        }
      }
    });
    files.add(GeneratedFile('lib/features/$feature/${feature}_injection.dart', _injection(feature, registrations, groups, pkg, options.domainLayer)));

    final bases = {for (final r in requests) _split(r.url).base};
    if (bases.length > 1) {
      notes.add('Requests use ${bases.length} different base URLs (${bases.where((b) => b.isNotEmpty).join(', ')}); '
          'every method is generated relative to one base, so adjust the others by hand.');
    }
    if (base.variable != null) {
      notes.add('Base URL is the variable {{${base.variable}}}: set it in lib/core/network/api_client.dart (or pass --dart-define=API_BASE_URL).');
    }
    notes.add('Add `dio` to pubspec.yaml${options.modelStyle == DartModelStyle.plain ? '' : ' (and the model style packages, then run build_runner)'}.');
    return ApiLayerResult(files, notes);
  }

  // --- reading a request -------------------------------------------------------

  ({String? origin, String? variable}) _commonBase(List<ApiSpecRequest> requests) {
    final counts = <String, int>{};
    for (final r in requests) {
      final b = _split(r.url).base;
      counts[b] = (counts[b] ?? 0) + 1;
    }
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final v = _variable.firstMatch(best);
    if (v != null && best.trim() == v[0]) return (origin: null, variable: v[1]);
    return (origin: best.isEmpty ? null : best, variable: null);
  }

  /// `{{baseUrl}}/users/:id?x=1` becomes base `{{baseUrl}}`, path `/users/:id`, query `x=1`.
  ({String base, String path, String query}) _split(String url) {
    var rest = url.trim();
    var query = '';
    final q = rest.indexOf('?');
    if (q >= 0) {
      query = rest.substring(q + 1);
      rest = rest.substring(0, q);
    }
    final varBase = RegExp(r'^\{\{[^{}]+\}\}').firstMatch(rest);
    if (varBase != null) return (base: varBase[0]!, path: rest.substring(varBase.end), query: query);
    final origin = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+').firstMatch(rest);
    if (origin != null) return (base: origin[0]!, path: rest.substring(origin.end), query: query);
    return (base: '', path: rest.startsWith('/') ? rest : '/$rest', query: query);
  }

  _Operation _operation(
    ApiSpecRequest r,
    Set<String> taken,
    ApiLayerOptions options,
    Map<String, GeneratedFile> modelFiles,
    String feature,
    List<String> notes,
  ) {
    var methodName = DartNames.camel(r.name, fallback: DartNames.camel('${r.method} ${r.url}'));
    final root = methodName;
    var n = 2;
    while (!taken.add(methodName)) {
      methodName = '$root$n';
      n++;
    }

    final parts = _split(r.url);
    final params = <_Param>[];
    final names = <String>{};
    String unique(String n0) {
      var name = n0;
      var i = 2;
      while (!names.add(name)) {
        name = '$n0$i';
        i++;
      }
      return name;
    }

    // Path: {{var}} and :var become required String parameters.
    var path = parts.path;
    path = path.replaceAllMapped(_variable, (m) {
      final name = unique(DartNames.camel(m[1]!));
      params.add(_Param(name, 'String', required: true, doc: 'Path variable {{${m[1]}}}'));
      return '\${$name}';
    });
    path = path.replaceAllMapped(RegExp(r'/:([A-Za-z_]\w*)'), (m) {
      final name = unique(DartNames.camel(m[1]!));
      params.add(_Param(name, 'String', required: true, doc: 'Path parameter :${m[1]}'));
      return '/\${$name}';
    });
    path = path.replaceAll("'", r"\'");

    // Query: request params plus whatever was written after '?' in the URL.
    final queryPairs = [...r.query];
    for (final piece in parts.query.split('&')) {
      if (piece.isEmpty) continue;
      final eq = piece.indexOf('=');
      queryPairs.add(eq < 0 ? (piece, '') : (piece.substring(0, eq), piece.substring(eq + 1)));
    }
    final queryEntries = <(String key, String name, bool nullable)>[];
    for (final (key, value) in queryPairs) {
      if (key.isEmpty) continue;
      final v = _variable.firstMatch(value);
      final whole = v != null && v[0] == value.trim();
      final name = unique(DartNames.camel(whole ? v[1]! : key));
      final fixed = whole || value.isEmpty ? null : value;
      params.add(_Param(name, 'String', required: false, defaultValue: fixed, doc: 'Query "$key"'));
      queryEntries.add((key, name, fixed == null));
    }

    // Headers that carry a variable (an API key, a tenant) become parameters too.
    final headerEntries = <(String key, String name)>[];
    for (final (key, value) in r.headers) {
      final v = _variable.firstMatch(value);
      if (key.isEmpty || v == null || v[0] != value.trim()) continue;
      if (key.toLowerCase() == 'authorization') continue; // handled by the interceptor
      final name = unique(DartNames.camel(v[1]!));
      params.add(_Param(name, 'String', required: true, doc: 'Header "$key"'));
      headerEntries.add((key, name));
    }

    // Body.
    final imports = <String>{};
    String? bodyExpr;
    var contentType = '';
    switch (r.bodyKind) {
      case ApiBodyKind.json:
        final decoded = _tryJson(_quoteVariables(r.bodyText));
        if (decoded is Map<String, dynamic>) {
          final model = _model('${DartNames.pascal(methodName)}Request', [jsonEncode(decoded)], options, modelFiles, feature, imports);
          if (model != null) {
            params.add(_Param('body', model, required: true, doc: 'Request body'));
            bodyExpr = 'body.toJson()';
            break;
          }
        }
        params.add(const _Param('body', 'Map<String, dynamic>', required: true, doc: 'Request body'));
        bodyExpr = 'body';
      case ApiBodyKind.text:
        params.add(const _Param('body', 'String', required: true, doc: 'Raw request body'));
        bodyExpr = 'body';
      case ApiBodyKind.form:
        params.add(const _Param('fields', 'Map<String, dynamic>', required: true, doc: 'Form fields'));
        bodyExpr = 'FormData.fromMap(fields)';
      case ApiBodyKind.urlEncoded:
        params.add(const _Param('fields', 'Map<String, dynamic>', required: true, doc: 'Form fields'));
        bodyExpr = 'fields';
        contentType = 'Headers.formUrlEncodedContentType';
      case ApiBodyKind.graphql:
        params.add(const _Param('variables', 'Map<String, dynamic>', required: false, doc: 'GraphQL variables'));
        bodyExpr = "{'query': _${methodName}Query, 'variables': variables}";
      case ApiBodyKind.none:
        break;
    }

    // Response type from the saved example.
    var responseType = 'dynamic';
    var parse = 'response.data';
    final example = r.exampleResponse?.trim();
    if (example != null && example.isNotEmpty) {
      final decoded = _tryJson(example);
      if (decoded is Map<String, dynamic> || (decoded is List && decoded.isNotEmpty && decoded.first is Map)) {
        final model = _model('${DartNames.pascal(methodName)}Response', [example], options, modelFiles, feature, imports);
        if (model != null) {
          if (decoded is List) {
            responseType = 'List<$model>';
            parse = '(response.data as List<dynamic>).map((e) => $model.fromJson(e as Map<String, dynamic>)).toList()';
          } else {
            responseType = model;
            parse = '$model.fromJson(response.data as Map<String, dynamic>)';
          }
        }
      } else if (decoded is List) {
        responseType = 'List<dynamic>';
        parse = 'response.data as List<dynamic>';
      }
    }

    // Required parameters first, as Dart style prefers.
    params.sort((a, b) => a.required == b.required ? 0 : (a.required ? -1 : 1));

    return _Operation(
      methodName: methodName,
      title: r.name,
      httpMethod: r.method.toUpperCase(),
      path: path.isEmpty ? '/' : path,
      params: params,
      queryEntries: queryEntries,
      headerEntries: headerEntries,
      bodyExpr: bodyExpr,
      contentType: contentType,
      graphqlQuery: r.bodyKind == ApiBodyKind.graphql ? r.bodyText : null,
      responseType: responseType,
      parseExpr: parse,
      modelImports: imports,
    );
  }

  /// Writes the model file(s) for [samples] and returns the root class name,
  /// or null when no class could be made.
  String? _model(
    String rootName,
    List<String> samples,
    ApiLayerOptions options,
    Map<String, GeneratedFile> modelFiles,
    String feature,
    Set<String> imports,
  ) {
    final modelOptions = DartModelOptions(style: options.modelStyle, allNullable: options.allNullable);
    final result = const DartModelGenerator().generate(samples, rootName: rootName, options: modelOptions);
    if (result.classCount == 0) return null;
    var root = DartNames.pascal(rootName);
    var path = 'lib/features/$feature/data/models/${DartNames.snake(root)}.dart';
    var n = 2;
    while (modelFiles.containsKey(path)) {
      root = '${DartNames.pascal(rootName)}$n';
      path = 'lib/features/$feature/data/models/${DartNames.snake(root)}.dart';
      n++;
    }
    final renamed = root == DartNames.pascal(rootName)
        ? result
        : const DartModelGenerator().generate(samples, rootName: root, options: modelOptions);
    modelFiles[path] = GeneratedFile(path, renamed.code);
    imports.add(path.substring('lib/'.length));
    return root;
  }

  Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// A body such as `{"id": {{id}}}` is not JSON until the variable is quoted.
  String _quoteVariables(String text) => text.replaceAllMapped(
        RegExp(r'("?)\{\{\s*([^{}\s]+)\s*\}\}("?)'),
        (m) => m[1]!.isNotEmpty && m[3]!.isNotEmpty ? m[0]! : '"{{${m[2]}}}"',
      );

  // --- code emission -------------------------------------------------------------

  String _apiClient(({String? origin, String? variable}) base) {
    final defaultBase = base.origin == null ? "''" : DartNames.quote(base.origin!);
    return '''import 'package:dio/dio.dart';

/// Builds the Dio instance every data source shares.
///
/// Pass [tokenProvider] to send `Authorization: Bearer <token>` on every call.
Dio createApiClient({String? baseUrl, Future<String?> Function()? tokenProvider}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: $defaultBase),
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ),
  );
  if (tokenProvider != null) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenProvider();
          if (token != null && token.isNotEmpty) options.headers['Authorization'] = 'Bearer \$token';
          handler.next(options);
        },
      ),
    );
  }
  return dio;
}
''';
  }

  static const _useCaseBase = '''abstract interface class UseCase<Output, Params> {
  Future<Output> call(Params params);
}

final class NoParams {
  const NoParams();
}
''';

  String _signature(_Operation op) {
    final positional = op.params.where((p) => p.required).toList();
    final optional = op.params.where((p) => !p.required).toList();
    if (op.params.isEmpty) return '';
    final b = StringBuffer('{');
    for (final p in [...positional, ...optional]) {
      b.write(p.required ? 'required ${p.type} ${p.name}, ' : '${p.type}${p.defaultValue == null ? '?' : ''} ${p.name}${p.defaultValue == null ? '' : ' = ${DartNames.quote(p.defaultValue!)}'}, ');
    }
    return '${b.toString().trimRight().replaceFirst(RegExp(r',$'), '')}}';
  }

  String _callArgs(_Operation op) => op.params.map((p) => '${p.name}: ${p.name}').join(', ');

  String _dataSource(String group, List<_Operation> ops, List<String> imports, String pkg) {
    final b = StringBuffer()
      ..writeln("import 'package:dio/dio.dart';")
      ..writeAll(imports.map((i) => '$i\n'))
      ..writeln()
      ..writeln('/// Remote calls of "$group". One method per request of the collection.')
      ..writeln('class ${group}RemoteDataSource {')
      ..writeln('  const ${group}RemoteDataSource(this._dio);')
      ..writeln()
      ..writeln('  final Dio _dio;');
    for (final op in ops) {
      if (op.graphqlQuery != null) {
        b
          ..writeln()
          ..writeln('  static const _${op.methodName}Query = r\'\'\'')
          ..writeln(op.graphqlQuery!.trim())
          ..writeln("''';");
      }
      b
        ..writeln()
        ..writeln('  /// ${op.title}')
        ..writeln('  ///')
        ..writeln('  /// `${op.httpMethod} ${op.path.replaceAll(r'${', '{')}`');
      for (final p in op.params) {
        if (p.doc != null) b.writeln('  /// - [${p.name}]: ${p.doc}');
      }
      b.writeln('  Future<${op.responseType}> ${op.methodName}(${_signature(op)}) async {');
      final query = op.queryEntries.isEmpty
          ? ''
          : ',\n      queryParameters: {\n${[for (final (key, name, nullable) in op.queryEntries) "        ${nullable ? 'if ($name != null) ' : ''}${DartNames.quote(key)}: $name,"].join('\n')}\n      }';
      final headers = op.headerEntries.isEmpty
          ? ''
          : "headers: {${[for (final (key, name) in op.headerEntries) '${DartNames.quote(key)}: $name'].join(', ')}}";
      final contentType = op.contentType.isEmpty ? '' : 'contentType: ${op.contentType}';
      final options = [headers, contentType].where((s) => s.isNotEmpty).join(', ');
      final data = op.bodyExpr == null ? '' : ',\n      data: ${op.bodyExpr}';
      final optionsArg = options.isEmpty ? '' : ',\n      options: Options($options)';
      switch (op.httpMethod) {
        case 'GET' || 'POST' || 'PUT' || 'PATCH' || 'DELETE' || 'HEAD':
          b.writeln("    final response = await _dio.${op.httpMethod.toLowerCase()}<dynamic>('${op.path}'$data$query$optionsArg);");
        default:
          final merged = [
            "method: '${op.httpMethod}'",
            if (options.isNotEmpty) options,
          ].join(', ');
          b.writeln("    final response = await _dio.request<dynamic>('${op.path}'$data$query,\n      options: Options($merged));");
      }
      b
        ..writeln('    return ${op.parseExpr};')
        ..writeln('  }');
    }
    b.writeln('}');
    return b.toString();
  }

  String _repositoryInterface(String group, List<_Operation> ops, List<String> imports, String pkg) {
    final b = StringBuffer()
      ..writeAll(imports.map((i) => '$i\n'))
      ..writeln()
      ..writeln('abstract interface class ${group}Repository {');
    for (final op in ops) {
      b.writeln('  Future<${op.responseType}> ${op.methodName}(${_signature(op)});');
    }
    b.writeln('}');
    return b.toString();
  }

  String _repositoryImpl(String group, List<_Operation> ops, String feature, String snake, List<String> imports, String pkg) {
    final b = StringBuffer()
      ..writeln("import 'package:$pkg/features/$feature/data/datasources/${snake}_remote_data_source.dart';")
      ..writeln("import 'package:$pkg/features/$feature/domain/repositories/${snake}_repository.dart';")
      ..writeAll(imports.map((i) => '$i\n'))
      ..writeln()
      ..writeln('final class ${group}RepositoryImpl implements ${group}Repository {')
      ..writeln('  const ${group}RepositoryImpl(this._remote);')
      ..writeln()
      ..writeln('  final ${group}RemoteDataSource _remote;');
    for (final op in ops) {
      b
        ..writeln()
        ..writeln('  @override')
        ..writeln('  Future<${op.responseType}> ${op.methodName}(${_signature(op)}) =>')
        ..writeln('      _remote.${op.methodName}(${_callArgs(op)});');
    }
    b.writeln('}');
    return b.toString();
  }

  String _useCase(String group, _Operation op, String feature, String snake, List<String> imports, String pkg) {
    final b = StringBuffer()
      ..writeln("import 'package:$pkg/core/usecases/usecase.dart';")
      ..writeln("import 'package:$pkg/features/$feature/domain/repositories/${snake}_repository.dart';")
      ..writeAll(imports.map((i) => '$i\n'))
      ..writeln();
    final paramsType = op.params.isEmpty ? 'NoParams' : '${op.useCaseName.replaceFirst('UseCase', '')}Params';
    if (op.params.isNotEmpty) {
      b.writeln('class $paramsType {');
      for (final p in op.params) {
        b.writeln('  final ${p.type}${p.required || p.defaultValue != null ? '' : '?'} ${p.name};');
      }
      b.writeln('  const $paramsType({');
      for (final p in op.params) {
        b.writeln('    ${p.required ? 'required ' : ''}this.${p.name}${p.defaultValue == null ? '' : ' = ${DartNames.quote(p.defaultValue!)}'},');
      }
      b
        ..writeln('  });')
        ..writeln('}')
        ..writeln();
    }
    b
      ..writeln('/// ${op.title}')
      ..writeln('final class ${op.useCaseName} implements UseCase<${op.responseType}, $paramsType> {')
      ..writeln('  const ${op.useCaseName}(this._repository);')
      ..writeln()
      ..writeln('  final ${group}Repository _repository;')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  Future<${op.responseType}> call($paramsType params) =>')
      ..writeln('      _repository.${op.methodName}(${op.params.map((p) => '${p.name}: params.${p.name}').join(', ')});')
      ..writeln('}');
    return b.toString();
  }

  String _injection(String feature, List<String> registrations, Map<String, List<_Operation>> groups, String pkg, bool domain) {
    final b = StringBuffer()
      ..writeln("import 'package:dio/dio.dart';")
      ..writeln("import 'package:get_it/get_it.dart';");
    groups.forEach((group, ops) {
      final snake = DartNames.snake(group);
      b.writeln("import 'package:$pkg/features/$feature/data/datasources/${snake}_remote_data_source.dart';");
      if (domain) {
        b
          ..writeln("import 'package:$pkg/features/$feature/data/repositories/${snake}_repository_impl.dart';")
          ..writeln("import 'package:$pkg/features/$feature/domain/repositories/${snake}_repository.dart';");
        for (final op in ops) {
          b.writeln("import 'package:$pkg/features/$feature/domain/usecases/${DartNames.snake(op.methodName)}_usecase.dart';");
        }
      }
    });
    b
      ..writeln()
      ..writeln('/// Registers this feature with GetIt. Register a [Dio] (see createApiClient) first.')
      ..writeln('void register${DartNames.pascal(feature)}Feature(GetIt sl) {')
      ..writeln('  sl')
      ..writeAll(registrations.map((r) => '$r\n'))
      ..writeln('  ;')
      ..writeln('}');
    return b.toString().replaceAll('\n  ;\n', ';\n').replaceFirst('  locator\n', '  locator\n');
  }
}

final class _Param {
  final String name;
  final String type;
  final bool required;
  final String? defaultValue;
  final String? doc;
  const _Param(this.name, this.type, {required this.required, this.defaultValue, this.doc});
}

final class _Operation {
  final String methodName;
  final String title;
  final String httpMethod;
  final String path;
  final List<_Param> params;
  final List<(String, String, bool)> queryEntries;
  final List<(String, String)> headerEntries;
  final String? bodyExpr;
  final String contentType;
  final String? graphqlQuery;
  final String responseType;
  final String parseExpr;
  final Set<String> modelImports;

  const _Operation({
    required this.methodName,
    required this.title,
    required this.httpMethod,
    required this.path,
    required this.params,
    required this.queryEntries,
    required this.headerEntries,
    required this.bodyExpr,
    required this.contentType,
    required this.graphqlQuery,
    required this.responseType,
    required this.parseExpr,
    required this.modelImports,
  });

  String get useCaseName => '${DartNames.pascal(methodName)}UseCase';
}
