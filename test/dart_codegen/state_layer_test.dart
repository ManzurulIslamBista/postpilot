// The state layer of the generated API layer (Provider, Riverpod, BLoC) for a collection with several groups: every file
// parses as Dart, every import of the generated package points at a generated file, no name is declared twice, and the
// classes have the shape the style promises. `none` stays exactly what the generator wrote before the option existed.
// ignore_for_file: depend_on_referenced_packages
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/dart_codegen/domain/entities/generated_file.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_layer_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/state_layer.dart';
import 'shop_api_fixture.dart';

ApiLayerResult _generate(StateLayerStyle style, {bool domain = true, DartModelStyle model = DartModelStyle.plain}) =>
    const ApiLayerGenerator().generate(
      'Shop',
      shopApiRequests(),
      options: ApiLayerOptions(packageName: 'shop_app', domainLayer: domain, stateLayer: style, modelStyle: model),
    );

GeneratedFile _file(ApiLayerResult r, String suffix) => r.files.firstWhere((f) => f.path.endsWith(suffix), orElse: () => fail('no file ends with $suffix'));

void main() {
  test('none writes no presentation file at all', () {
    final plain = const ApiLayerGenerator().generate('Shop', shopApiRequests(), options: const ApiLayerOptions(packageName: 'shop_app'));
    final none = _generate(StateLayerStyle.none);
    expect(none.files.map((f) => f.path), plain.files.map((f) => f.path));
    expect(none.files.any((f) => f.path.contains('presentation/') || f.path.contains('core/state/')), isFalse);
    expect(none.notes.any((n) => n.startsWith('State layer')), isFalse);
  });

  for (final style in [StateLayerStyle.provider, StateLayerStyle.riverpod, StateLayerStyle.bloc]) {
    for (final domain in [true, false]) {
      group('${style.label}, domain layer: $domain', () {
        late ApiLayerResult result;
        setUp(() => result = _generate(style, domain: domain));

        test('every file parses and every import of the generated package resolves', () {
          final paths = result.files.map((f) => f.path).toSet();
          for (final f in result.files) {
            final parsed = parseString(content: f.content, path: f.path, throwIfDiagnostics: false);
            expect(parsed.errors, isEmpty, reason: '${f.path}: ${parsed.errors.map((e) => e.message).join('; ')}\n${f.content}');
            for (final m in RegExp(r"import 'package:shop_app/([^']+)';").allMatches(f.content)) {
              expect(paths, contains('lib/${m[1]}'), reason: '${f.path} imports ${m[1]}, which was not generated');
            }
          }
        });

        test('one state file per group, in the folder of the style', () {
          final folder = switch (style) {
            StateLayerStyle.provider => 'view_models/%_view_model.dart',
            StateLayerStyle.riverpod => 'providers/%_providers.dart',
            _ => 'cubits/%_cubits.dart',
          };
          for (final group in ['users', 'orders', 'shop']) {
            expect(result.files.map((f) => f.path), contains('lib/features/shop/presentation/${folder.replaceAll('%', group)}'));
          }
        });

        test('calls the repository, or the data source without the domain layer', () {
          final source = domain ? 'UsersRepository' : 'UsersRemoteDataSource';
          final text = _file(result, style == StateLayerStyle.provider ? 'users_view_model.dart' : style == StateLayerStyle.riverpod ? 'users_providers.dart' : 'users_cubits.dart').content;
          expect(text, contains(source));
          expect(text, isNot(contains(domain ? 'UsersRemoteDataSource' : 'UsersRepository')));
        });

        test('no top-level name is declared twice across the state files', () {
          final seen = <String, String>{};
          for (final f in result.files.where((f) => f.path.contains('/presentation/'))) {
            // `class X`, `sealed class X`, `final class X` and `final xProvider = ...`.
            for (final m in RegExp(r'^(?:(?:sealed |final |abstract )*class (\w+)|final (\w+) =)', multiLine: true).allMatches(f.content)) {
              final name = (m[1] ?? m[2])!;
              expect(seen.containsKey(name), isFalse, reason: '$name is declared in ${f.path} and in ${seen[name]}');
              seen[name] = f.path;
            }
          }
          expect(seen, isNotEmpty);
        });

        test('says which package to add and how to hook the classes up', () {
          final note = result.notes.firstWhere((n) => n.startsWith('State layer'));
          expect(note, contains('`${style.dependencyCommand}`'));
          expect(note, isNot(RegExp(r'\^?\d+\.\d+\.\d+')), reason: 'no version number is invented');
        });
      });
    }
  }

  group('Provider', () {
    final result = _generate(StateLayerStyle.provider);
    final text = _file(result, 'users_view_model.dart').content;

    test('a view model per group with one CallState per call', () {
      expect(text, contains('class UsersViewModel extends ChangeNotifier {'));
      expect(text, contains("import 'package:flutter/foundation.dart' show ChangeNotifier;"));
      expect(text, contains('CallState<ListUsersResponse> listUsersState = const CallIdle();'));
      expect(text, contains('CallState<GetUserResponse> getUserState = const CallIdle();'));
      expect(text, contains('CallState<dynamic> deleteUserState = const CallIdle();'));
      expect(text, contains('CallState<List<dynamic>> renameUserState = const CallIdle();'));
    });

    test('a call forwards its arguments to the repository and keeps loading, data and error', () {
      expect(text, contains("Future<void> listUsers({String? page, String limit = '20', String status = 'active'}) {"));
      expect(text, contains("_source.listUsers(page: page, limit: limit, status: status)"));
      expect(text, contains('write(CallLoading<T>(read().data));'));
      expect(text, contains('write(CallSuccess<T>(data));'));
      expect(text, contains('write(CallFailure<T>(error, read().data, stackTrace));'));
      expect(text, contains('if (_runs[key] != id) return;'), reason: 'an older call must not replace a newer answer');
      expect(text, contains('if (!_disposed) notifyListeners();'));
    });

    test('reads can be repeated, actions cannot', () {
      expect(text, contains('Future<void> refreshListUsers()'));
      expect(text, contains('Future<void> refreshGetUser()'));
      expect(text, isNot(contains('refreshCreateUser')));
      expect(text, isNot(contains('refreshDeleteUser')));
      expect(text, contains("_repeatListUsers = () => this.listUsers(page: page, limit: limit, status: status);"));
    });

    test('the shared call state is declared once and flagged as shared', () {
      final shared = _file(result, 'core/state/call_state.dart');
      expect(shared.shared, isTrue);
      expect(shared.content, contains('sealed class CallState<T>'));
      for (final name in ['CallIdle', 'CallLoading', 'CallSuccess', 'CallFailure']) {
        expect(shared.content, contains('final class $name<T> extends CallState<T>'));
      }
      expect(result.files.where((f) => f.path.endsWith('call_state.dart')), hasLength(1));
    });
  });

  group('Riverpod', () {
    final result = _generate(StateLayerStyle.riverpod);
    final text = _file(result, 'users_providers.dart').content;

    test('an AsyncNotifier and a provider per call, no code generation, no shared file', () {
      expect(text, contains('class ListUsersNotifier extends AsyncNotifier<ListUsersResponse?> {'));
      expect(text, contains('final listUsersProvider = AsyncNotifierProvider<ListUsersNotifier, ListUsersResponse?>(ListUsersNotifier.new);'));
      expect(text, contains('class DeleteUserNotifier extends AsyncNotifier<dynamic> {'), reason: 'dynamic already allows null');
      expect(text, isNot(contains('@riverpod')));
      expect(text, isNot(contains('part ')));
      expect(result.files.any((f) => f.path.contains('core/state/')), isFalse);
    });

    test('the repository comes from GetIt and can be overridden in tests', () {
      expect(text, contains('final usersRepositoryProvider = Provider<UsersRepository>((ref) => GetIt.I<UsersRepository>());'));
      expect(text, contains('overrideWithValue(fake)'));
    });

    test('state is the AsyncValue: the old result stays while a call repeats, a late answer is dropped', () {
      expect(text, contains('state = const AsyncLoading();'));
      expect(text, isNot(contains('copyWithPrevious')), reason: 'internal API of riverpod; the notifier keeps the previous value by itself');
      expect(text, contains('AsyncValue.guard<ListUsersResponse?>(call)'));
      expect(text, contains('if (id == _runs) state = result;'));
      expect(text, contains('this.ref.read(usersRepositoryProvider).listUsers(page: page, limit: limit, status: status)'));
      expect(text, contains('Future<void> refresh() => _repeat?.call() ?? Future<void>.value();'));
    });

    test('imports only the names it uses from the package, so a DTO cannot clash with it', () {
      expect(text, contains("import 'package:flutter_riverpod/flutter_riverpod.dart' show "));
      expect(text, isNot(contains("import 'package:flutter_riverpod/flutter_riverpod.dart';")));
    });
  });

  group('BLoC', () {
    final result = _generate(StateLayerStyle.bloc);
    final text = _file(result, 'users_cubits.dart').content;

    test('a Cubit per call over the sealed CallState', () {
      expect(text, contains('class ListUsersCubit extends Cubit<CallState<ListUsersResponse>> {'));
      expect(text, contains('ListUsersCubit(this._source) : super(const CallIdle());'));
      expect(text, contains('class DeleteUserCubit extends Cubit<CallState<dynamic>> {'));
      expect(_file(result, 'core/state/call_state.dart').shared, isTrue);
    });

    test('never emits after close, never lets an older call win', () {
      expect(text, contains('if (isClosed) return;'));
      expect(text, contains('if (id == _runs && !isClosed) emit(CallSuccess<ListUsersResponse>(data));'));
      expect(text, contains('emit(CallFailure<ListUsersResponse>(error, state.data, stackTrace));'));
      expect(text, contains('_repeat = () => this.run(page: page, limit: limit, status: status);'));
    });
  });

  group('names', () {
    const request = ApiSpecRequest(
      name: 'Settings',
      method: 'GET',
      url: '{{baseUrl}}/settings',
      exampleResponse: '{"provider":{"id":1},"cubit":{"x":1},"asyncValue":{"y":1},"callState":{"z":1}}',
    );

    String model(StateLayerStyle style) {
      final r = const ApiLayerGenerator().generate('X', const [request], options: ApiLayerOptions(stateLayer: style));
      return r.files.firstWhere((f) => f.path.endsWith('settings_response.dart')).content;
    }

    test('a DTO does not take a name the state package or call_state.dart exports', () {
      final riverpod = model(StateLayerStyle.riverpod);
      expect(riverpod, contains('class ProviderModel '));
      expect(riverpod, contains('class AsyncValueModel '));
      expect(riverpod, isNot(contains('class Provider ')));
      final bloc = model(StateLayerStyle.bloc);
      expect(bloc, contains('class CubitModel '));
      expect(bloc, contains('class CallStateModel '));
      expect(model(StateLayerStyle.provider), contains('class CallStateModel '));
    });

    test('without a state layer the names stay as they were', () {
      final none = model(StateLayerStyle.none);
      expect(none, contains('class Provider '));
      expect(none, contains('class Cubit '));
    });
  });

  test('the result carries the DTO files for the diff', () {
    final result = _generate(StateLayerStyle.none);
    expect(result.models.keys, contains('lib/features/shop/data/models/list_users_response.dart'));
    expect(result.models['lib/features/shop/data/models/list_users_response.dart']!.root, 'ListUsersResponse');
    expect(result.models['lib/features/shop/data/models/create_user_request.dart']!.root, 'CreateUserRequest');
  });
}
