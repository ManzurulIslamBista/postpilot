import 'dart:convert';
import '../../../git_sync/domain/services/secret_names.dart';
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

  /// The name of an authentication the generated client cannot perform on its own
  /// (`Basic Auth`, `OAuth 2.0`...), so the generated code can say it was left out.
  /// Bearer tokens are not listed here: they go through `tokenProvider`.
  final String? unsupportedAuth;

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
    this.unsupportedAuth,
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

  /// A `{{variable}}` or a `/:param` inside a path.
  static final _pathToken = RegExp(r'\{\{\s*([^{}\s]+)\s*\}\}|/:([A-Za-z_]\w*)');

  static final _bearer = RegExp(r'^bearer\s', caseSensitive: false);

  /// Names the data sources see from Dio (and from this layer itself), which a DTO
  /// class must not take: `Options` is the call's options, not a `{"options": {}}` object.
  static const _importedTypes = {
    'Dio', 'Options', 'FormData', 'Headers', 'Response', 'BaseOptions', 'RequestOptions', 'Interceptor',
    'InterceptorsWrapper', 'ResponseType', 'CancelToken', 'DioException', 'MultipartFile', 'Transformer',
    'UseCase', 'NoParams', 'GetIt',
  };

  /// Headers the HTTP client sets itself; copying them would break the request.
  static const _managedHeaders = {
    'content-length', 'host', 'connection', 'transfer-encoding', 'expect', 'keep-alive', 'upgrade', 'te', 'trailer',
  };

  ApiLayerResult generate(String collectionName, List<ApiSpecRequest> requests, {ApiLayerOptions options = const ApiLayerOptions()}) {
    final notes = <String>[];
    final feature = DartNames.snake(collectionName, fallback: 'api');
    // A package name is a lowercase identifier; anything else would break every import line.
    final pkg = DartNames.snake(options.packageName, fallback: 'app');
    final files = <GeneratedFile>[];
    if (requests.isEmpty) return const ApiLayerResult([], ['The collection has no requests.']);

    final base = _commonBase(requests);
    // These two are shared by every generated feature (and by a project's own code), so a
    // writer must never replace a copy that already exists.
    files.add(GeneratedFile('lib/core/network/api_client.dart', _apiClient(base), shared: true));
    if (options.domainLayer) files.add(const GeneratedFile('lib/core/usecases/usecase.dart', _useCaseBase, shared: true));

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
    _nameUseCases(groups);

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
          files.add(GeneratedFile('lib/features/$feature/domain/usecases/${op.useCaseFile}',
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
    if (base.templated != null) {
      notes.add('The base URL ${base.templated} contains variables, so no default was written: set the real one in '
          'lib/core/network/api_client.dart (or pass --dart-define=API_BASE_URL).');
    }
    _noteUntranslated(groups, notes);
    notes.add('Add `dio` to pubspec.yaml${options.modelStyle == DartModelStyle.plain ? '' : ' (and the model style packages, then run build_runner)'}.');
    return ApiLayerResult(files, notes);
  }

  /// A use case's class and file name must be unique across the whole collection,
  /// but a method name is only unique inside its group: folders "Users" and
  /// "Orders" can each hold a "Get all". A name more than one group uses gets its
  /// group as a prefix (`UsersGetAll`, `OrdersGetAll`).
  void _nameUseCases(Map<String, List<_Operation>> groups) {
    final counts = <String, int>{};
    for (final ops in groups.values) {
      for (final op in ops) {
        counts.update(DartNames.pascal(op.methodName), (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final usedNames = <String>{};
    final usedFiles = <String>{};
    groups.forEach((group, ops) {
      for (final op in ops) {
        final plain = DartNames.pascal(op.methodName);
        final stem = counts[plain]! > 1 ? '$group$plain' : plain;
        var name = stem;
        var n = 2;
        while (!usedNames.add(name) || !usedFiles.add(DartNames.snake(name))) {
          name = '$stem$n';
          n++;
        }
        op.useCaseStem = name;
      }
    });
  }

  /// Everything a request had that could not be turned into code is said so in
  /// the generated method's comment; this lists the distinct reasons once.
  void _noteUntranslated(Map<String, List<_Operation>> groups, List<String> notes) {
    final byReason = <String, List<String>>{};
    for (final ops in groups.values) {
      for (final op in ops) {
        for (final reason in op.untranslated) {
          byReason.putIfAbsent(reason, () => []).add(op.title);
        }
      }
    }
    byReason.forEach((reason, titles) {
      final more = titles.length > 3 ? ' and ${titles.length - 3} more' : '';
      notes.add('Not translated: $reason (${titles.take(3).join(', ')}$more).');
    });
  }

  // --- reading a request -------------------------------------------------------

  ({String? origin, String? variable, String? templated}) _commonBase(List<ApiSpecRequest> requests) {
    final counts = <String, int>{};
    for (final r in requests) {
      final b = _split(r.url).base;
      counts[b] = (counts[b] ?? 0) + 1;
    }
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final v = _variable.firstMatch(best);
    if (v != null && best.trim() == v[0]) return (origin: null, variable: v[1], templated: null);
    // `https://{{host}}` is not an address anyone can call, so it is not written as the default.
    if (v != null) return (origin: null, variable: null, templated: best);
    return (origin: best.isEmpty ? null : best, variable: null, templated: null);
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
    // `response` is the local the generated method reads the answer into.
    final names = <String>{'response'};
    String unique(String n0) {
      var name = n0;
      var i = 2;
      while (!names.add(name)) {
        name = '$n0$i';
        i++;
      }
      return name;
    }

    final untranslated = <String>[];

    // Path: {{var}} and :var become required String parameters, URL-encoded where they
    // are used. The rest is literal text, so a `$`, `'` or `\` in it (`/odata/$metadata`)
    // is escaped and cannot start an interpolation.
    final pathCode = StringBuffer();
    final pathDoc = StringBuffer();
    final pathNames = <String, String>{};
    var last = 0;
    for (final m in _pathToken.allMatches(parts.path)) {
      final literal = parts.path.substring(last, m.start);
      pathCode.write(DartNames.escape(literal));
      pathDoc.write(literal);
      final isVariable = m[1] != null;
      final raw = (isVariable ? m[1] : m[2])!;
      // The same variable twice in one path is one argument.
      var name = pathNames[raw];
      if (name == null) {
        name = unique(DartNames.camel(raw));
        pathNames[raw] = name;
        params.add(_Param(name, 'String', required: true, doc: isVariable ? 'Path variable {{$raw}}' : 'Path parameter :$raw'));
      }
      if (!isVariable) {
        pathCode.write('/');
        pathDoc.write('/');
      }
      pathCode.write('\${Uri.encodeComponent($name)}');
      pathDoc.write('{$name}');
      last = m.end;
    }
    final tail = parts.path.substring(last);
    pathCode.write(DartNames.escape(tail));
    pathDoc.write(tail);

    // Query: request params plus whatever was written after '?' in the URL.
    final queryPairs = [...r.query];
    for (final piece in parts.query.split('&')) {
      if (piece.isEmpty) continue;
      final eq = piece.indexOf('=');
      queryPairs.add(eq < 0 ? (piece, '') : (piece.substring(0, eq), piece.substring(eq + 1)));
    }
    final queryEntries = <(String key, String expr, String? onlyIfSet)>[];
    for (final (key, value) in queryPairs) {
      if (key.isEmpty) continue;
      final v = _variable.firstMatch(value);
      final whole = v != null && v[0] == value.trim();
      if (v != null && !whole) {
        // `q={{term}}*`: the value is built from the arguments, there is no single one to pass.
        final expr = _interpolate(value, (variable) {
          final name = unique(DartNames.camel(variable));
          params.add(_Param(name, 'String', required: true, doc: 'Part of query "$key" ({{$variable}})'));
          return name;
        });
        queryEntries.add((key, expr, null));
        continue;
      }
      final name = unique(DartNames.camel(whole ? v[1]! : key));
      // An API key saved in the request is not copied into source code.
      final secret = !whole && value.isNotEmpty && SecretNames.isSecretQuery(key) && SecretNames.hasLiteralSecret(value);
      final fixed = whole || value.isEmpty || secret ? null : value;
      params.add(_Param(
        name,
        'String',
        required: false,
        defaultValue: fixed,
        doc: secret ? 'Query "$key" (the value saved in the request is not copied into generated code)' : 'Query "$key"',
      ));
      queryEntries.add((key, name, fixed == null ? name : null));
    }

    // Headers. A value with {{variables}} becomes arguments; a static value is written as it is,
    // unless it is a credential (that becomes an argument too, the saved secret stays out of the code).
    final headerEntries = <(String key, String expr)>[];
    void putHeader(String key, String expr) {
      headerEntries.removeWhere((e) => e.$1.toLowerCase() == key.toLowerCase());
      headerEntries.add((key, expr));
    }

    for (final (rawKey, value) in r.headers) {
      final key = rawKey.trim();
      if (key.isEmpty) continue;
      final lower = key.toLowerCase();
      if (lower == 'authorization' && _bearer.hasMatch(value.trim())) continue; // the interceptor sends it
      if (_managedHeaders.contains(lower)) {
        untranslated.add('the header "$key" is set by the HTTP client itself');
        continue;
      }
      if (lower == 'content-type' && (r.bodyKind == ApiBodyKind.form || r.bodyKind == ApiBodyKind.urlEncoded)) {
        untranslated.add('the Content-Type of a form body (Dio sets it, with the boundary for multipart)');
        continue;
      }
      if (_variable.hasMatch(value)) {
        final whole = _variable.firstMatch(value)![0] == value.trim();
        if (whole) {
          final name = unique(DartNames.camel(_variable.firstMatch(value)![1]!));
          params.add(_Param(name, 'String', required: true, doc: 'Header "$key"'));
          putHeader(key, name);
        } else {
          putHeader(key, _interpolate(value, (variable) {
            final name = unique(DartNames.camel(variable));
            params.add(_Param(name, 'String', required: true, doc: 'Part of header "$key" ({{$variable}})'));
            return name;
          }));
        }
      } else if ((SecretNames.isSecretHeader(key) && SecretNames.hasLiteralSecret(value)) || SecretNames.looksLikeCredential(value)) {
        final name = unique(DartNames.camel(key));
        params.add(_Param(name, 'String', required: true, doc: 'Header "$key" (the value saved in the request is not copied into generated code)'));
        putHeader(key, name);
      } else {
        putHeader(key, DartNames.quote(value));
      }
    }
    if (r.unsupportedAuth != null) {
      untranslated.add('${r.unsupportedAuth} authentication: add it to createApiClient, for instance as an interceptor');
    }

    // Body.
    final imports = <String>{};
    String? bodyExpr;
    var contentType = '';
    switch (r.bodyKind) {
      case ApiBodyKind.json:
        final decoded = _tryJson(_quoteVariables(r.bodyText));
        final bodyName = unique('body');
        if (decoded is Map<String, dynamic>) {
          final model = _model('${DartNames.pascal(methodName)}Request', [jsonEncode(decoded)], options, modelFiles, feature, imports);
          if (model != null) {
            params.add(_Param(bodyName, model, required: true, doc: 'Request body'));
            bodyExpr = '$bodyName.toJson()';
            break;
          }
        }
        params.add(_Param(bodyName, decoded is List ? 'List<dynamic>' : 'Map<String, dynamic>', required: true, doc: 'Request body'));
        bodyExpr = bodyName;
      case ApiBodyKind.text:
        final bodyName = unique('body');
        params.add(_Param(bodyName, 'String', required: true, doc: 'Raw request body'));
        bodyExpr = bodyName;
      case ApiBodyKind.form:
        final fields = unique('fields');
        params.add(_Param(fields, 'Map<String, dynamic>', required: true, doc: 'Form fields'));
        bodyExpr = 'FormData.fromMap($fields)';
      case ApiBodyKind.urlEncoded:
        final fields = unique('fields');
        params.add(_Param(fields, 'Map<String, dynamic>', required: true, doc: 'Form fields'));
        bodyExpr = fields;
        contentType = 'Headers.formUrlEncodedContentType';
      case ApiBodyKind.graphql:
        final variables = unique('variables');
        params.add(_Param(variables, 'Map<String, dynamic>', required: false, doc: 'GraphQL variables'));
        bodyExpr = "{'query': _${methodName}Query, 'variables': $variables}";
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

    // Required parameters first, as Dart style prefers; each group keeps the order it was added in.
    final ordered = [...params.where((p) => p.required), ...params.where((p) => !p.required)];

    final path = pathCode.toString();
    return _Operation(
      methodName: methodName,
      title: r.name,
      httpMethod: r.method.toUpperCase(),
      path: path.isEmpty ? '/' : path,
      docPath: pathDoc.isEmpty ? '/' : pathDoc.toString(),
      params: ordered,
      queryEntries: queryEntries,
      headerEntries: headerEntries,
      bodyExpr: bodyExpr,
      contentType: contentType,
      graphqlQuery: r.bodyKind == ApiBodyKind.graphql ? r.bodyText : null,
      responseType: responseType,
      parseExpr: parse,
      modelImports: imports,
      untranslated: untranslated,
    );
  }

  /// [text] as a Dart string literal in which every `{{variable}}` is replaced by
  /// `${name}`, [argument] giving the name of the argument that holds it.
  String _interpolate(String text, String Function(String variable) argument) {
    final b = StringBuffer("'");
    var last = 0;
    for (final m in _variable.allMatches(text)) {
      b
        ..write(DartNames.escape(text.substring(last, m.start)))
        ..write('\${${argument(m[1]!)}}');
      last = m.end;
    }
    b
      ..write(DartNames.escape(text.substring(last)))
      ..write("'");
    return b.toString();
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
    final modelOptions = DartModelOptions(style: options.modelStyle, allNullable: options.allNullable, avoidClassNames: _importedTypes);
    final result = const DartModelGenerator().generate(samples, rootName: rootName, options: modelOptions);
    if (result.classCount == 0) return null;
    final wanted = DartNames.className(rootName, fallback: 'Root', also: _importedTypes);
    var root = wanted;
    var path = 'lib/features/$feature/data/models/${DartNames.snake(root)}.dart';
    var n = 2;
    while (modelFiles.containsKey(path)) {
      root = '$wanted$n';
      path = 'lib/features/$feature/data/models/${DartNames.snake(root)}.dart';
      n++;
    }
    final renamed = root == wanted
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

  String _apiClient(({String? origin, String? variable, String? templated}) base) {
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
      ..writeln('/// Remote calls of "${_docText(group)}". One method per request of the collection.')
      ..writeln('class ${group}RemoteDataSource {')
      ..writeln('  const ${group}RemoteDataSource(this._dio);')
      ..writeln()
      ..writeln('  final Dio _dio;');
    for (final op in ops) {
      if (op.graphqlQuery != null) {
        final query = op.graphqlQuery!.trim();
        b.writeln();
        if (query.contains("'''")) {
          // A raw ''' string cannot hold ''', so this one is an ordinary literal.
          b.writeln('  static const _${op.methodName}Query = ${DartNames.quote(query)};');
        } else {
          b
            ..writeln('  static const _${op.methodName}Query = r\'\'\'')
            ..writeln(query)
            ..writeln("''';");
        }
      }
      b
        ..writeln()
        ..writeln('  /// ${_docText(op.title)}')
        ..writeln('  ///')
        ..writeln('  /// `${op.httpMethod} ${_docText(op.docPath)}`');
      for (final p in op.params) {
        if (p.doc != null) b.writeln('  /// - [${p.name}]: ${_docText(p.doc!)}');
      }
      for (final reason in op.untranslated) {
        b.writeln('  /// NOT TRANSLATED: ${_docText(reason)}.');
      }
      b.writeln('  Future<${op.responseType}> ${op.methodName}(${_signature(op)}) async {');
      final query = op.queryEntries.isEmpty
          ? ''
          : ',\n      queryParameters: {\n${[for (final (key, expr, onlyIfSet) in op.queryEntries) "        ${onlyIfSet == null ? '' : 'if ($onlyIfSet != null) '}${DartNames.quote(key)}: $expr,"].join('\n')}\n      }';
      final headers = op.headerEntries.isEmpty
          ? ''
          : "headers: {${[for (final (key, expr) in op.headerEntries) '${DartNames.quote(key)}: $expr'].join(', ')}}";
      final contentType = op.contentType.isEmpty ? '' : 'contentType: ${op.contentType}';
      final options = [headers, contentType].where((s) => s.isNotEmpty).join(', ');
      final data = op.bodyExpr == null ? '' : ',\n      data: ${op.bodyExpr}';
      final optionsArg = options.isEmpty ? '' : ',\n      options: Options($options)';
      switch (op.httpMethod) {
        case 'GET' || 'POST' || 'PUT' || 'PATCH' || 'DELETE' || 'HEAD':
          b.writeln("    final response = await _dio.${op.httpMethod.toLowerCase()}<dynamic>('${op.path}'$data$query$optionsArg);");
        default:
          final merged = [
            "method: ${DartNames.quote(op.httpMethod)}",
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

  /// Text for a `///` line: one line, and nothing that reads as a comment terminator.
  String _docText(String text) => text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ');

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
    final paramsType = op.params.isEmpty ? 'NoParams' : '${op.useCaseStem}Params';
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
      ..writeln('/// ${_docText(op.title)}')
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
          b.writeln("import 'package:$pkg/features/$feature/domain/usecases/${op.useCaseFile}';");
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
    return b.toString().replaceAll('\n  ;\n', ';\n');
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

  /// The path as Dart string-literal text (escaped, `${...}` for arguments).
  final String path;

  /// The same path for a comment: `/users/{userId}`.
  final String docPath;
  final List<_Param> params;

  /// Query key, the Dart expression for its value, and the argument that must be
  /// non-null for it to be sent (null when it always is).
  final List<(String, String, String?)> queryEntries;
  final List<(String, String)> headerEntries;
  final String? bodyExpr;
  final String contentType;
  final String? graphqlQuery;
  final String responseType;
  final String parseExpr;
  final Set<String> modelImports;

  /// What the request has that the generated method does not do, for its comment.
  final List<String> untranslated;

  /// Unique over the whole collection, set once every operation is known.
  String? useCaseStem;

  _Operation({
    required this.methodName,
    required this.title,
    required this.httpMethod,
    required this.path,
    required this.docPath,
    required this.params,
    required this.queryEntries,
    required this.headerEntries,
    required this.bodyExpr,
    required this.contentType,
    required this.graphqlQuery,
    required this.responseType,
    required this.parseExpr,
    required this.modelImports,
    required this.untranslated,
  });

  String get _stem => useCaseStem ?? DartNames.pascal(methodName);
  String get useCaseName => '${_stem}UseCase';
  String get useCaseFile => '${DartNames.snake(_stem)}_usecase.dart';
}
