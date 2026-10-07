import '../../../dart_codegen/domain/entities/generated_file.dart';
import '../../../dart_codegen/domain/services/dart_model_generator.dart' show DartModelStyle;
import '../../../dart_codegen/domain/services/dart_names.dart';
import '../../../dart_codegen/domain/services/state_layer.dart';
import '../entities/odoo_model_info.dart';
import 'odoo_client_templates.dart';
import 'odoo_dart_generator.dart';
import 'odoo_state_templates.dart';

class OdooClientOptions {
  /// Where the client goes, below the project root. Its files import each other by relative path, so any folder works.
  final String folder;

  /// How the model classes serialise (plain, json_serializable or freezed); see [OdooDartOptions.style].
  final DartModelStyle modelStyle;

  /// Also write `OdooRpcClient`, for Odoo 18 and older (a login session instead of an API key).
  final bool includeJsonRpc;

  /// A view model, set of notifiers or cubit per model on top of the repositories.
  final StateLayerStyle stateLayer;

  /// Keep computed (non-stored) fields too.
  final bool includeComputed;

  /// The fields to keep per model, by name; a model that is not listed keeps every stored field. `id` is always kept.
  final Map<String, Set<String>> fieldsByModel;

  /// Leave `binary` fields out: a list read would download every image.
  final bool skipBinary;

  const OdooClientOptions({
    this.folder = 'lib/odoo',
    this.modelStyle = DartModelStyle.plain,
    this.includeJsonRpc = false,
    this.stateLayer = StateLayerStyle.none,
    this.includeComputed = false,
    this.fieldsByModel = const {},
    this.skipBinary = true,
  });
}

final class OdooClientResult {
  final List<GeneratedFile> files;

  /// What the person should know: packages to add, models that could not be generated, relations left out.
  final List<String> notes;

  /// The class written for each model, by model name.
  final Map<String, String> classNames;

  const OdooClientResult(this.files, this.notes, this.classNames);
}

/// Generates a Flutter-ready Odoo client from the `fields_get` of the models a person picked: model classes, a pure-Dart
/// `OdooClient` (Dio; JSON-2 with a bearer API key, optionally the JSON-RPC session of Odoo 18 and older as a second
/// class), a typed `Domain` builder, the x2many `Command` helpers, an `OdooException` hierarchy and a repository per
/// model (paging, typed many2one refs, UTC datetimes, `false` meaning empty), optionally with a state layer on top.
///
/// No credential is ever written: the URL, the database and the key are constructor arguments of the generated client.
final class OdooClientGenerator {
  const OdooClientGenerator();

  /// Names the generated support code declares; a model class must not take them.
  static const _reserved = {
    'Domain', 'Command', 'OdooClient', 'OdooRpcClient', 'OdooRef', 'OdooPage', 'OdooException', 'OdooAuthException',
    'OdooAccessException', 'OdooValidationException', 'OdooMissingRecordException', 'OdooUserException',
    'OdooSessionExpiredException', 'OdooServerException', 'OdooNetworkException',
  };

  /// The models a many2one field of [model] points at (its stored fields only, or [fieldNames]): what "include related
  /// models" adds. [model] itself is not in the result.
  static Set<String> relatedModels(OdooModelInfo model, {Set<String>? fieldNames, bool includeComputed = false}) => {
        for (final f in model.fields)
          if (f.type == 'many2one' &&
              f.relation != null &&
              f.relation != model.model &&
              (includeComputed || f.stored) &&
              (fieldNames?.contains(f.name) ?? true))
            f.relation!,
      };

  OdooClientResult generate(List<OdooModelInfo> models, {OdooClientOptions options = const OdooClientOptions()}) {
    final folder = options.folder.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    final root = folder.isEmpty ? 'lib/odoo' : folder;
    final notes = <String>[];
    final files = <GeneratedFile>[];
    final classNames = <String, String>{};

    final seen = <String>{};
    final unique = [for (final m in models) if (seen.add(m.model)) m];
    if (unique.isEmpty) {
      return const OdooClientResult([], ['Choose at least one model to generate a client for.'], {});
    }

    final avoid = {..._reserved, ...options.stateLayer.reservedNames};
    final usedClasses = <String>{};
    final usedFiles = <String>{};
    final modelDart = const OdooDartGenerator();
    GeneratedFile? support;
    final generated = <({String model, String className, String fileName})>[];

    for (final info in unique) {
      var className = DartNames.className(info.model, fallback: 'Model', also: avoid);
      var n = 2;
      final wantedClass = className;
      while (!usedClasses.add(className)) {
        className = '$wantedClass$n';
        n++;
      }
      var fileName = DartNames.snake(info.model, fallback: 'model');
      final wantedFile = fileName;
      n = 2;
      while (!usedFiles.add(fileName)) {
        fileName = '${wantedFile}_$n';
        n++;
      }
      final selected = options.fieldsByModel[info.model];
      final dartFiles = modelDart.generate(
        info,
        options: OdooDartOptions(
          fieldNames: selected == null ? null : {...selected, 'id'},
          includeComputed: options.includeComputed,
          style: options.modelStyle,
          folder: '$root/models',
          className: className,
          fileName: fileName,
          skipBinary: options.skipBinary,
        ),
      );
      files.add(dartFiles.first);
      support ??= dartFiles.last;
      classNames[info.model] = className;
      generated.add((model: info.model, className: className, fileName: fileName));
      if (info.field('id') == null) {
        notes.add('${info.model} has no id field in what was read: its repository cannot find a record by id.');
      }
      if (selected != null && selected.isEmpty) {
        notes.add('No field of ${info.model} was selected, so only its id is generated.');
      }
    }
    files.add(support!);

    files
      ..add(GeneratedFile('$root/core/odoo_exception.dart', OdooClientTemplates.exceptions, shared: true))
      ..add(GeneratedFile('$root/core/odoo_domain.dart', OdooClientTemplates.domain, shared: true))
      ..add(GeneratedFile('$root/core/odoo_commands.dart', OdooClientTemplates.commands, shared: true))
      ..add(GeneratedFile('$root/core/odoo_page.dart', OdooClientTemplates.page, shared: true))
      ..add(GeneratedFile(
        '$root/core/odoo_client.dart',
        OdooClientTemplates.clientHeader + (options.includeJsonRpc ? OdooClientTemplates.rpcClient : ''),
        shared: true,
      ));

    for (final g in generated) {
      files.add(GeneratedFile('$root/repositories/${g.fileName}_repository.dart', _repository(g.model, g.className, g.fileName)));
    }

    if (options.stateLayer != StateLayerStyle.none) {
      if (options.stateLayer == StateLayerStyle.riverpod) {
        files.add(GeneratedFile('$root/state/odoo_providers.dart', OdooStateTemplates.riverpodProviders, shared: true));
      }
      final (template, suffix) = switch (options.stateLayer) {
        StateLayerStyle.provider => (OdooStateTemplates.provider, 'view_model'),
        StateLayerStyle.riverpod => (OdooStateTemplates.riverpod, 'providers'),
        StateLayerStyle.bloc => (OdooStateTemplates.bloc, 'cubit'),
        StateLayerStyle.none => ('', ''),
      };
      for (final g in generated) {
        files.add(GeneratedFile(
          '$root/state/${g.fileName}_$suffix.dart',
          OdooStateTemplates.render(template, {
            'Class': g.className,
            'model': g.model,
            'file': g.fileName,
            'lower': DartNames.camel(g.className),
          }),
        ));
      }
    }

    files.add(GeneratedFile('$root/README.md', _readme(root, generated.first, options, generated.length), shared: true));

    final chosen = {for (final m in unique) m.model};
    final left = <String>{
      for (final m in unique)
        ...relatedModels(m, fieldNames: options.fieldsByModel[m.model], includeComputed: options.includeComputed).where((r) => !chosen.contains(r)),
    };
    if (left.isNotEmpty) {
      final shown = (left.toList()..sort()).take(6).join(', ');
      notes.add('Many2one fields point at ${left.length} model${left.length == 1 ? '' : 's'} that ${left.length == 1 ? 'is' : 'are'} not generated '
          '($shown${left.length > 6 ? ', ...' : ''}); they are read as OdooRef (id and name). Tick "include related models" to get classes for them.');
    }
    notes.add('Add dio to pubspec.yaml: `dart pub add dio`. The client has no other dependency.');
    switch (options.modelStyle) {
      case DartModelStyle.plain:
        break;
      case DartModelStyle.jsonSerializable:
        notes.add('Model style json_serializable: `dart pub add json_annotation`, `dart pub add --dev build_runner json_serializable`, then `dart run build_runner build`.');
      case DartModelStyle.freezed:
        notes.add('Model style freezed: `dart pub add freezed_annotation json_annotation`, `dart pub add --dev build_runner freezed json_serializable`, then `dart run build_runner build`.');
    }
    final command = options.stateLayer.dependencyCommand;
    if (command != null) notes.add('State layer (${options.stateLayer.label}): run `$command`.');
    notes.add('The API key, password and database are constructor arguments of OdooClient${options.includeJsonRpc ? ' / OdooRpcClient' : ''}: '
        'none of them is written into the generated code. Read them from secure storage or --dart-define.');
    return OdooClientResult(files, notes, classNames);
  }

  String _repository(String model, String className, String fileName) => OdooStateTemplates.render(_repositoryTemplate, {
        'Class': className,
        'model': DartNames.escape(model),
        'file': fileName,
      });

  static const _repositoryTemplate = r'''import '../core/odoo_client.dart';
import '../core/odoo_domain.dart';
import '../core/odoo_exception.dart';
import '../core/odoo_page.dart';
import '../models/%file%.dart';
import '../models/odoo_json.dart';

/// Typed access to the `%model%` records: search with paging, read one, create, update, delete and a many2one name search.
///
/// It works with an [OdooClient] (JSON-2, Odoo 19 and later) and with an `OdooRpcClient` (Odoo 18 and older) alike. Every
/// method throws an [OdooException] and nothing else.
class %Class%Repository {
  const %Class%Repository(this._client);

  /// The technical name Odoo knows the model by.
  static const model = '%model%';

  final OdooClient _client;

  /// One page of the records matching [domain], [limit] at a time from [offset] on. With [withCount] the page also knows
  /// how many records match in all (one more call).
  Future<OdooPage<%Class%>> search({
    Domain domain = Domain.all,
    int limit = 20,
    int offset = 0,
    String? order,
    bool withCount = false,
  }) async {
    final rows = await _client.searchRead(model, domain: domain, fields: %Class%.fieldNames, limit: limit, offset: offset, order: order);
    final total = withCount ? await _client.searchCount(model, domain: domain) : null;
    return OdooPage([for (final row in rows) %Class%.fromJson(row)], offset: offset, limit: limit, total: total);
  }

  /// How many records match [domain].
  Future<int> count({Domain domain = Domain.all}) => _client.searchCount(model, domain: domain);

  /// The record with [id], or null when it does not exist (or was deleted).
  Future<%Class%?> getById(int id) async {
    try {
      final rows = await _client.read(model, [id], fields: %Class%.fieldNames);
      return rows.isEmpty ? null : %Class%.fromJson(rows.first);
    } on OdooMissingRecordException {
      return null;
    }
  }

  /// Creates the record from [item] and reads it back, so server-side defaults and computed fields are in the result.
  ///
  /// A boolean that is false and an empty x2many are what an unfilled model holds, not a decision, so they are left out and
  /// Odoo's own defaults apply (a new record is active). [extra] is added to the values as it is: use it to force one
  /// (`{'active': false}`) and for the x2many commands (`Command.create`, `Command.link`...).
  Future<%Class%> create(%Class% item, {Map<String, Object?> extra = const {}}) async {
    final values = <String, Object?>{
      for (final entry in item.toJson().entries)
        if (entry.value != false && !(entry.value is List && (entry.value as List).isEmpty)) entry.key: entry.value,
      ...extra,
    };
    final ids = await _client.create(model, [values]);
    final created = await getById(ids.first);
    if (created == null) {
      throw OdooMissingRecordException('Odoo created $model ${ids.first} but it cannot be read back: check this user\'s read access.');
    }
    return created;
  }

  /// Writes [values] (only the fields to change, by their Odoo names) to the record and reads it back.
  Future<%Class%> update(int id, Map<String, Object?> values) async {
    await _client.write(model, [id], values);
    final updated = await getById(id);
    if (updated == null) throw OdooMissingRecordException('$model $id does not exist (any more).');
    return updated;
  }

  /// Deletes the record. This cannot be undone.
  Future<void> delete(int id) async {
    await _client.unlink(model, [id]);
  }

  /// The records whose name contains [text] as `OdooRef(id, name)`, the way a many2one box searches.
  Future<List<OdooRef>> nameSearch(String text, {Domain domain = Domain.all, int limit = 8}) async {
    final pairs = await _client.nameSearch(model, name: text, domain: domain, limit: limit);
    return [for (final (id, name) in pairs) OdooRef(id, name)];
  }
}
''';

  String _readme(String root, ({String model, String className, String fileName}) first, OdooClientOptions options, int count) {
    final repo = '${first.className}Repository';
    final variable = DartNames.camel(first.className);
    final b = StringBuffer()
      ..writeln('# Odoo client')
      ..writeln()
      ..writeln('Generated by PostPilot for $count model${count == 1 ? '' : 's'}. It has no dependency but `dio` (`dart pub add dio`).')
      ..writeln()
      ..writeln('## Connect')
      ..writeln()
      ..writeln('The URL, the database and the key are arguments: nothing secret is written into this folder. Read the key from secure')
      ..writeln('storage or `--dart-define`, never commit it.')
      ..writeln()
      ..writeln('```dart')
      ..writeln("import 'package:your_app/${_relative(root)}core/odoo_client.dart';")
      ..writeln()
      ..writeln('final client = OdooClient(')
      ..writeln("  baseUrl: 'https://mycompany.odoo.com',")
      ..writeln("  database: 'mycompany',")
      ..writeln("  apiKey: const String.fromEnvironment('ODOO_API_KEY'), // Odoo: Preferences > Account Security > New API Key")
      ..writeln(');')
      ..writeln('```');
    if (options.includeJsonRpc) {
      b
        ..writeln()
        ..writeln('Odoo 18 and older have no JSON-2 API: use the session client, which has the same methods.')
        ..writeln()
        ..writeln('```dart')
        ..writeln('final client = OdooRpcClient(')
        ..writeln("  baseUrl: 'https://mycompany.example.com',")
        ..writeln("  database: 'mycompany',")
        ..writeln("  login: 'admin',")
        ..writeln("  password: const String.fromEnvironment('ODOO_PASSWORD'), // a password or an API key")
        ..writeln(');')
        ..writeln('```');
    }
    b
      ..writeln()
      ..writeln('## Use')
      ..writeln()
      ..writeln('```dart')
      ..writeln('final $variable = $repo(client);')
      ..writeln('final page = await $variable.search(domain: Domain.ilike(\'name\', \'azure\') & Domain.eq(\'active\', true), limit: 20);')
      ..writeln('final next = await $variable.search(offset: page.nextOffset);')
      ..writeln('```')
      ..writeln()
      ..writeln('- `Domain` builds search domains (`&`, `|`, `~`, nesting); `Command` writes the one2many / many2many commands.')
      ..writeln('- Every call throws an `OdooException`: `OdooAccessException`, `OdooValidationException`, `OdooMissingRecordException`,')
      ..writeln('  `OdooUserException`, `OdooSessionExpiredException`, `OdooAuthException`, `OdooServerException` or `OdooNetworkException`.')
      ..writeln('- An empty Odoo value is `false`: the models read it as null (or as `false` for a boolean). A many2one is an `OdooRef`')
      ..writeln('  (id and display name). Datetimes are UTC.');
    final command = options.stateLayer.dependencyCommand;
    if (command != null) {
      b
        ..writeln()
        ..writeln('## State (${options.stateLayer.label})')
        ..writeln()
        ..writeln('Run `$command`. Each model has a list state with loading, error, paging, refresh, filter and create / update / delete:')
        ..writeln()
        ..writeln('```dart');
      switch (options.stateLayer) {
        case StateLayerStyle.provider:
          b.writeln('ChangeNotifierProvider(create: (_) => ${first.className}ListViewModel($repo(client))..loadFirstPage(), child: const MyList());');
        case StateLayerStyle.riverpod:
          b
            ..writeln('ProviderScope(overrides: [odooClientProvider.overrideWithValue(client)], child: const MyApp());')
            ..writeln('final list = ref.watch(${DartNames.camel(first.className)}ListProvider); // AsyncValue<${first.className}ListState>')
            // An AsyncNotifier already has a method called update.
            ..writeln('ref.read(${DartNames.camel(first.className)}ListProvider.notifier).updateRecord(id, {\'name\': \'New name\'});');
        case StateLayerStyle.bloc:
          b.writeln('BlocProvider(create: (_) => ${first.className}ListCubit($repo(client))..load(), child: const MyList());');
        case StateLayerStyle.none:
          break;
      }
      b.writeln('```');
      if (options.stateLayer == StateLayerStyle.riverpod) {
        b
          ..writeln()
          ..writeln('Riverpod 3 tries a provider again when its first load throws (up to ten times, with a growing delay) before the')
          ..writeln('error shows. To see a failed first load at once, give the scope `retry: (count, error) => null`.');
      }
    }
    return b.toString();
  }

  /// The folder below `lib/`, for a `package:your_app/...` import in the README (the package name is not known here).
  String _relative(String root) => root.startsWith('lib/') ? '${root.substring('lib/'.length)}/' : '$root/';
}
