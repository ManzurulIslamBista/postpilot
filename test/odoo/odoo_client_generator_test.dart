// The generated Flutter client for Odoo, for res.partner and the models around it: every combination of model style,
// state layer and transport parses as Dart, every relative import resolves to a generated file, nothing secret is in
// the output, and the pieces have the shape the README promises. (The generated code is also compiled and exercised
// against a fake server outside this test: see the report of the change.)
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/features/dart_codegen/domain/entities/generated_file.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/state_layer.dart';
import 'package:postpilot/features/odoo/domain/entities/odoo_model_info.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_client_generator.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_dart_generator.dart';
import 'support/fake_odoo.dart';

OdooModelInfo _model(String name, Map<String, Map<String, Object?>> fields) => OdooModelInfo.parse(name, jsonEncode(fields))!;

final _partner = _model('res.partner', partnerFields);
final _country = _model('res.country', countryFields);
final _category = _model('res.partner.category', categoryFields);

OdooClientResult _generate({
  List<OdooModelInfo>? models,
  DartModelStyle style = DartModelStyle.plain,
  StateLayerStyle state = StateLayerStyle.none,
  bool rpc = false,
  String folder = 'lib/odoo',
  Map<String, Set<String>> fields = const {},
}) =>
    const OdooClientGenerator().generate(
      models ?? [_partner, _country],
      options: OdooClientOptions(folder: folder, modelStyle: style, stateLayer: state, includeJsonRpc: rpc, fieldsByModel: fields),
    );

GeneratedFile _file(OdooClientResult r, String path) => r.files.firstWhere((f) => f.path == path, orElse: () => fail('$path was not generated'));

void main() {
  group('every combination is valid Dart that hangs together', () {
    for (final style in DartModelStyle.values) {
      for (final state in StateLayerStyle.values) {
        for (final rpc in [false, true]) {
          test('${style.name}, ${state.name}, JSON-RPC client: $rpc', () {
            final result = _generate(style: style, state: state, rpc: rpc, models: [_partner, _country, _category]);
            final paths = result.files.map((f) => f.path).toSet();
            expect(paths, hasLength(result.files.length), reason: 'no file is generated twice');
            for (final f in result.files.where((f) => f.path.endsWith('.dart'))) {
              final parsed = parseString(content: f.content, path: f.path, throwIfDiagnostics: false);
              expect(parsed.errors, isEmpty, reason: '${f.path}: ${parsed.errors.map((e) => e.message).join('; ')}\n${f.content}');
              for (final m in RegExp(r"^(import|part) '([^']+)';", multiLine: true).allMatches(f.content)) {
                final target = m[2]!;
                if (target.contains(':')) continue; // dart: and package: imports
                final resolved = p.posix.normalize(p.posix.join(p.posix.dirname(f.path), target));
                // A `part` of json_serializable / freezed is written by build_runner, not by us.
                if (m[1] == 'part') continue;
                expect(paths, contains(resolved), reason: '${f.path} imports $target, which is not generated');
              }
            }
            // The client file has the second class only when asked for.
            final client = _file(result, 'lib/odoo/core/odoo_client.dart').content;
            expect(client.contains('class OdooRpcClient extends OdooClient'), rpc);
          });
        }
      }
    }
  });

  group('what is generated', () {
    final result = _generate(models: [_partner, _country, _category]);

    test('the core files, the models and one repository per model', () {
      expect(
        result.files.map((f) => f.path),
        containsAll([
          'lib/odoo/core/odoo_client.dart',
          'lib/odoo/core/odoo_exception.dart',
          'lib/odoo/core/odoo_domain.dart',
          'lib/odoo/core/odoo_commands.dart',
          'lib/odoo/core/odoo_page.dart',
          'lib/odoo/models/odoo_json.dart',
          'lib/odoo/models/res_partner.dart',
          'lib/odoo/models/res_country.dart',
          'lib/odoo/models/res_partner_category.dart',
          'lib/odoo/repositories/res_partner_repository.dart',
          'lib/odoo/repositories/res_country_repository.dart',
          'lib/odoo/repositories/res_partner_category_repository.dart',
          'lib/odoo/README.md',
        ]),
      );
      expect(result.classNames, {'res.partner': 'ResPartner', 'res.country': 'ResCountry', 'res.partner.category': 'ResPartnerCategory'});
    });

    test('shared support files are flagged so a writer never replaces the project\'s own', () {
      final shared = {for (final f in result.files) if (f.shared) f.path};
      expect(shared, {
        'lib/odoo/core/odoo_client.dart',
        'lib/odoo/core/odoo_exception.dart',
        'lib/odoo/core/odoo_domain.dart',
        'lib/odoo/core/odoo_commands.dart',
        'lib/odoo/core/odoo_page.dart',
        'lib/odoo/models/odoo_json.dart',
        'lib/odoo/README.md',
      });
      final riverpod = _generate(state: StateLayerStyle.riverpod);
      expect(_file(riverpod, 'lib/odoo/state/odoo_providers.dart').shared, isTrue);
      expect(_file(riverpod, 'lib/odoo/state/res_partner_providers.dart').shared, isFalse);
    });

    test('the model reads Odoo JSON: false for empty, [id, name] many2one, UTC datetimes, binary fields left out', () {
      final model = _file(result, 'lib/odoo/models/res_partner.dart').content;
      expect(model, contains('class ResPartner {'));
      expect(model, contains('final OdooRef? parentId;'));
      expect(model, contains("writeDate: odooDateTime(json['write_date'])"));
      expect(model, contains("isCompany: odooBool(json['is_company'])"));
      expect(model, isNot(contains('image1920')), reason: 'a list read must not download every image');
      expect(model, contains("static const fieldNames = ['id',"));
    });

    test('credentials are constructor arguments and are not in any file', () {
      final all = result.files.map((f) => f.content).join('\n');
      final client = _file(result, 'lib/odoo/core/odoo_client.dart').content;
      expect(client, contains('required String apiKey,'));
      expect(client, contains("'Authorization': 'bearer \$_apiKey'"));
      expect(client, contains("'X-Odoo-Database': database"));
      expect(all, isNot(contains('key-123')));
      expect(all, isNot(contains('pw-456')));
      expect(all, isNot(RegExp(r"bearer [A-Za-z0-9_\-]{8,}")), reason: 'a literal bearer token');
      final rpc = _file(_generate(rpc: true), 'lib/odoo/core/odoo_client.dart').content;
      expect(rpc, contains('required String password,'));
      expect(rpc, contains('/web/session/authenticate'));
      expect(rpc, contains(r'/web/dataset/call_kw/$model/$method'));
    });

    test('the client has every call the repositories need', () {
      final client = _file(result, 'lib/odoo/core/odoo_client.dart').content;
      for (final signature in [
        'Future<List<Map<String, dynamic>>> searchRead(',
        'Future<List<Map<String, dynamic>>> read(',
        'Future<int> searchCount(',
        'Future<List<int>> create(',
        'Future<bool> write(',
        'Future<bool> unlink(',
        'Future<Map<String, dynamic>> fieldsGet(',
        'Future<List<(int, String)>> nameSearch(',
      ]) {
        expect(client, contains(signature));
      }
      expect(client, contains(r'/json/2/$model/$method'));
    });

    test('every Odoo error maps to a class of the hierarchy', () {
      final text = _file(result, 'lib/odoo/core/odoo_exception.dart').content;
      for (final name in [
        'OdooAuthException',
        'OdooAccessException',
        'OdooValidationException',
        'OdooMissingRecordException',
        'OdooUserException',
        'OdooSessionExpiredException',
        'OdooServerException',
        'OdooNetworkException',
      ]) {
        expect(text, contains('final class $name extends OdooException'));
      }
      expect(text, contains("'AccessError' || 'Forbidden'"));
      expect(text, contains("'ValidationError'"));
      expect(text, contains("'MissingError'"));
      expect(text, contains("'UserError' || 'Warning' || 'RedirectWarning'"));
      expect(text, contains("short == 'SessionExpiredException'"));
    });

    test('Domain has the operators, &, |, ~ and nesting; Command has the seven x2many commands', () {
      final domain = _file(result, 'lib/odoo/core/odoo_domain.dart').content;
      for (final needle in ['Domain operator &(', 'Domain operator |(', 'Domain operator ~(', 'static Domain and(', 'static Domain or(', 'Domain not()', 'static Domain ilike(', 'static Domain inList(', 'child_of']) {
        expect(domain, contains(needle));
      }
      final commands = _file(result, 'lib/odoo/core/odoo_commands.dart').content;
      for (final needle in ['[0, 0, values]', '[1, id, values]', '[2, id, 0]', '[3, id, 0]', '[4, id, 0]', '[5, 0, 0]', '[6, 0, ids]']) {
        expect(commands, contains(needle));
      }
    });

    test('a repository pages, reads one, creates, updates, deletes and name-searches', () {
      final repo = _file(result, 'lib/odoo/repositories/res_partner_repository.dart').content;
      expect(repo, contains("static const model = 'res.partner';"));
      expect(repo, contains('Future<OdooPage<ResPartner>> search({'));
      expect(repo, contains('Future<ResPartner?> getById(int id)'));
      expect(repo, contains('Future<ResPartner> create(ResPartner item, {Map<String, Object?> extra = const {}})'));
      expect(repo, contains('Future<ResPartner> update(int id, Map<String, Object?> values)'));
      expect(repo, contains('Future<void> delete(int id)'));
      expect(repo, contains('Future<List<OdooRef>> nameSearch(String text'));
      expect(repo, contains('on OdooMissingRecordException'));
    });

    test('the README shows the wiring with the key and the database as arguments', () {
      final readme = _file(result, 'lib/odoo/README.md').content;
      expect(readme, contains('dart pub add dio'));
      expect(readme, contains("apiKey: const String.fromEnvironment('ODOO_API_KEY')"));
      expect(readme, contains("database: 'mycompany'"));
      expect(readme, contains('ResPartnerRepository(client)'));
      expect(readme, isNot(contains('OdooRpcClient(')));
      expect(_file(_generate(rpc: true), 'lib/odoo/README.md').content, contains('OdooRpcClient('));
    });
  });

  group('options', () {
    test('a model keeps only the chosen fields, and always its id', () {
      final result = _generate(models: [_partner], fields: {'res.partner': {'name', 'email'}});
      final model = _file(result, 'lib/odoo/models/res_partner.dart').content;
      expect(model, contains("static const fieldNames = ['id', 'email', 'name'];"));
      expect(model, isNot(contains('parentId')));
    });

    test('the folder moves every file, and the imports still resolve', () {
      final result = _generate(folder: '/lib/data/odoo/');
      expect(result.files.every((f) => f.path.startsWith('lib/data/odoo/')), isTrue);
      expect(result.files.map((f) => f.path), contains('lib/data/odoo/repositories/res_partner_repository.dart'));
    });

    test('the model style is the existing one: plain is byte for byte the Odoo model generator', () {
      final viaClient = _file(_generate(models: [_partner]), 'lib/odoo/models/res_partner.dart').content;
      final direct = const OdooDartGenerator()
          .generate(_partner, options: const OdooDartOptions(folder: 'lib/odoo/models', skipBinary: true))
          .first
          .content;
      expect(viaClient, direct);
      final fallback = const OdooDartGenerator().generate(_partner).first.content;
      expect(const OdooDartGenerator().generate(_partner).map((f) => f.path), ['lib/models/res_partner.dart', 'lib/models/odoo_json.dart']);
      expect(fallback, contains('class ResPartner {'));
    });

    test('json_serializable and freezed read Odoo JSON through the same helpers', () {
      final json = _file(_generate(models: [_partner], style: DartModelStyle.jsonSerializable), 'lib/odoo/models/res_partner.dart').content;
      expect(json, contains('@JsonSerializable()'));
      expect(json, contains("part 'res_partner.g.dart';"));
      expect(json, contains("@JsonKey(name: 'parent_id', fromJson: OdooRef.from, toJson: odooRefToJson, includeIfNull: false)"));
      expect(json, contains("@JsonKey(name: 'is_company', fromJson: odooBool)"));
      expect(json, contains("@JsonKey(name: 'write_date', fromJson: odooDateTime, toJson: odooDateTimeToJson, includeToJson: false, includeIfNull: false)"));
      expect(json, contains('@JsonKey(fromJson: odooInt, includeToJson: false, includeIfNull: false)\n  final int? id;'));
      expect(json, contains('fromJson: ResPartnerType.fromOdoo, toJson: ResPartnerType.toOdoo'));
      expect(json, contains('static String? toOdoo(ResPartnerType? value) => value?.odoo;'));
      expect(json, contains(r'_$ResPartnerFromJson(json)'));
      final freezed = _file(_generate(models: [_partner], style: DartModelStyle.freezed), 'lib/odoo/models/res_partner.dart').content;
      expect(freezed, contains('@freezed'));
      expect(freezed, contains(r'abstract class ResPartner with _$ResPartner {'));
      expect(freezed, contains("part 'res_partner.freezed.dart';"));
      expect(freezed, contains("@JsonKey(name: 'is_company', fromJson: odooBool) @Default(false) bool isCompany,"));
      expect(freezed, contains("@JsonKey(name: 'child_ids', fromJson: odooIds) @Default(<int>[]) List<int> childIds,"));
      expect(freezed, contains('}) = _ResPartner;'));
    });

    test('class and file names that would collide are numbered, and a name the support code uses is avoided', () {
      OdooModelInfo tiny(String name) => _model(name, {'id': {'type': 'integer', 'string': 'ID', 'store': true}});
      final result = _generate(models: [tiny('a.b_c'), tiny('a_b.c'), tiny('domain'), tiny('odoo.client')]);
      expect(result.classNames, {'a.b_c': 'ABC', 'a_b.c': 'ABC2', 'domain': 'DomainModel', 'odoo.client': 'OdooClientModel'});
      expect(result.files.map((f) => f.path), containsAll(['lib/odoo/models/a_b_c.dart', 'lib/odoo/models/a_b_c_2.dart', 'lib/odoo/models/domain.dart']));
      for (final f in result.files.where((f) => f.path.endsWith('.dart'))) {
        expect(parseString(content: f.content, path: f.path, throwIfDiagnostics: false).errors, isEmpty, reason: f.path);
      }
    });

    test('nothing chosen says so, the same model twice is one', () {
      final empty = const OdooClientGenerator().generate(const []);
      expect(empty.files, isEmpty);
      expect(empty.notes.single, contains('Choose at least one model'));
      expect(_generate(models: [_partner, _partner]).classNames, hasLength(1));
    });
  });

  group('related models', () {
    test('the many2one targets of the stored fields, not the model itself, not x2many', () {
      expect(OdooClientGenerator.relatedModels(_partner), {'res.country', 'res.users'});
      expect(OdooClientGenerator.relatedModels(_partner, fieldNames: {'name', 'country_id'}), {'res.country'});
      expect(OdooClientGenerator.relatedModels(_partner, fieldNames: {'name'}), isEmpty);
      expect(OdooClientGenerator.relatedModels(_country), isEmpty);
    });

    test('models that are left out are named in a note; none when they are all there', () {
      final left = _generate(models: [_partner]).notes.firstWhere((n) => n.contains('point at'));
      expect(left, contains('res.country'));
      expect(left, contains('res.users'));
      final users = _model('res.users', {'id': {'type': 'integer', 'string': 'ID', 'store': true}});
      final complete = _generate(models: [_partner, _country, users]);
      expect(complete.notes.any((n) => n.contains('point at')), isFalse);
    });
  });

  group('state layer', () {
    test('Provider: a ChangeNotifier list view model per model', () {
      final r = _generate(models: [_partner], state: StateLayerStyle.provider);
      final text = _file(r, 'lib/odoo/state/res_partner_view_model.dart').content;
      expect(text, contains('class ResPartnerListViewModel extends ChangeNotifier {'));
      for (final needle in ['loadFirstPage()', 'loadMore()', 'refresh()', 'applyFilter(', 'Future<ResPartner?> create(', 'Future<ResPartner?> update(', 'Future<bool> delete(', 'bool isLoading', 'bool hasMore', 'Object? error;']) {
        expect(text, contains(needle));
      }
      expect(r.notes.any((n) => n.contains('`dart pub add provider`')), isTrue);
    });

    test('Riverpod: AsyncNotifier and providers, the client is overridden by the app', () {
      final r = _generate(models: [_partner], state: StateLayerStyle.riverpod);
      final text = _file(r, 'lib/odoo/state/res_partner_providers.dart').content;
      expect(text, contains('class ResPartnerListNotifier extends AsyncNotifier<ResPartnerListState> {'));
      expect(text, contains('final resPartnerListProvider = AsyncNotifierProvider<ResPartnerListNotifier, ResPartnerListState>(ResPartnerListNotifier.new);'));
      expect(text, contains('final resPartnerRepositoryProvider = Provider<ResPartnerRepository>((ref) => ResPartnerRepository(ref.watch(odooClientProvider)));'));
      expect(text, isNot(contains('@riverpod')));
      expect(text, contains('Future<ResPartner?> updateRecord(int id, Map<String, Object?> values)'), reason: 'AsyncNotifier has an update of its own');
      expect(text, isNot(contains('copyWithPrevious')), reason: 'internal API of riverpod');
      expect(text, contains('retry: (count, error) => null'), reason: 'Riverpod 3 retries a failing first load: the file says how to turn it off');
      final readme = _file(r, 'lib/odoo/README.md').content;
      expect(readme, contains('ListProvider.notifier).updateRecord(id,'));
      expect(readme, contains('retry: (count, error) => null'));
      final providers = _file(r, 'lib/odoo/state/odoo_providers.dart').content;
      expect(providers, contains('UnimplementedError('));
      expect(providers, isNot(RegExp(r"OdooClient\(")), reason: 'no client with a key is built in generated code');
      expect(r.notes.any((n) => n.contains('`dart pub add flutter_riverpod`')), isTrue);
    });

    test('BLoC: a Cubit with sealed states', () {
      final r = _generate(models: [_partner], state: StateLayerStyle.bloc);
      final text = _file(r, 'lib/odoo/state/res_partner_cubit.dart').content;
      expect(text, contains('sealed class ResPartnerListState {'));
      for (final name in ['ResPartnerListInitial', 'ResPartnerListLoading', 'ResPartnerListLoaded', 'ResPartnerListFailure']) {
        expect(text, contains('final class $name extends ResPartnerListState'));
      }
      expect(text, contains('class ResPartnerListCubit extends Cubit<ResPartnerListState> {'));
      expect(r.notes.any((n) => n.contains('`dart pub add flutter_bloc`')), isTrue);
    });

    test('every style guards against a late answer and the action methods keep the list in step', () {
      for (final style in [StateLayerStyle.provider, StateLayerStyle.riverpod, StateLayerStyle.bloc]) {
        final r = _generate(models: [_partner], state: style);
        final text = r.files.firstWhere((f) => f.path.startsWith('lib/odoo/state/res_partner_')).content;
        expect(text, contains('_loads'), reason: style.name);
        expect(text, contains('item.id == id ? updated : item'), reason: style.name);
        expect(text, contains('if (item.id != id) item'), reason: style.name);
      }
    });

    test('none writes no state file', () {
      expect(_generate().files.any((f) => f.path.contains('/state/')), isFalse);
    });
  });
}
