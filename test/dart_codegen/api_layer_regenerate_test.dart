// Regenerate with diff, end to end: a collection is generated, its classes are remembered, a saved example changes, and
// the next generation starts with what changed (breaking or not, with migration notes). The store is the real settings
// table in memory; the view model and the Dart Studio tab are the real ones.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/dart_codegen/data/settings_model_snapshot_store.dart';
import 'package:postpilot/features/dart_codegen/domain/repositories/model_snapshot_store.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_layer_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/model_schema_diff.dart';
import 'package:postpilot/features/dart_codegen/domain/usecases/build_api_layer_usecase.dart';
import 'package:postpilot/features/dart_codegen/presentation/view_models/api_layer_view_model.dart';
import 'package:postpilot/features/dart_codegen/presentation/widgets/dart_studio_dialog.dart';
import 'package:postpilot/features/dart_codegen/presentation/widgets/model_diff_panel.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import 'package:provider/provider.dart';
import '../support/fake_workplace_repository.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';

const _v1 = '[{"id":1,"name":"Ann","email":"a@example.com","total":5}]';
const _v2 = '[{"id":1,"name":"Ann","mail":"a@example.com","total":5.5,"vip":true}]';

ResponseExampleEntity _example(int requestId, String body) =>
    ResponseExampleEntity(id: 0, requestId: requestId, name: 'OK', statusCode: 200, headers: const {}, body: body, savedAt: DateTime.utc(2026, 1, 1));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryDb db;
  late AppDatabase settings;
  late SettingsModelSnapshotStore store;
  late int collection;
  late int listRequest;

  /// Replaces the saved example of "List users", as if the endpoint had changed and the user saved a new response.
  Future<void> saveExample(String body) async {
    db.examples.removeWhere((e) => e.requestId == listRequest);
    await db.exampleRepository.add(_example(listRequest, body));
  }

  setUp(() async {
    await locator.reset();
    db = InMemoryDb();
    settings = AppDatabase.forTesting(NativeDatabase.memory());
    store = SettingsModelSnapshotStore(settings.settingsDao);
    collection = await db.collectionRepository.createCollection('Shop');
    listRequest = await addRequest(db, collection, 'List users', url: '{{baseUrl}}/users');
    await saveExample(_v1);
  });

  tearDown(() async {
    await locator.reset();
    await settings.close();
  });

  ApiLayerViewModel newViewModel() => ApiLayerViewModel(BuildApiLayerUseCase(db.loader, db.exampleRepository), store)..collectionId = collection;

  group('the view model', () {
    test('the first generation has no baseline and nothing to compare', () async {
      final vm = newViewModel();
      await vm.generate();
      expect(vm.files, isNotEmpty);
      expect(vm.hasBaseline, isFalse);
      expect(vm.diff, isNull);
      expect(vm.canRemember, isTrue);
    });

    test('after a version is remembered, the next generation shows what changed and migration notes', () async {
      final vm = newViewModel();
      await vm.generate();
      await vm.rememberCurrent();
      expect(vm.hasBaseline, isTrue);
      expect(vm.diff!.isEmpty, isTrue);

      await saveExample(_v2);
      await vm.generate();
      final diff = vm.diff!;
      final byKind = {for (final c in diff.changes) c.kind: c};
      expect(byKind.keys.toSet(), {SchemaChangeKind.fieldRenamed, SchemaChangeKind.typeChanged, SchemaChangeKind.fieldAdded});
      expect((byKind[SchemaChangeKind.fieldRenamed]!.oldField, byKind[SchemaChangeKind.fieldRenamed]!.field), ('email', 'mail'));
      expect((byKind[SchemaChangeKind.typeChanged]!.before, byKind[SchemaChangeKind.typeChanged]!.after), ('int', 'double'));
      expect(byKind[SchemaChangeKind.fieldAdded]!.field, 'vip');
      expect(byKind[SchemaChangeKind.fieldAdded]!.breaking, isFalse, reason: 'a response gained a field');
      expect(diff.breaking, hasLength(2));
      expect(diff.byClass.keys, ['ListUsersResponse']);
      expect(diff.migrationNotes(), contains('Replace `.email` with `.mail`'));
    });

    test('remembering again makes the new shape the baseline', () async {
      final vm = newViewModel();
      await vm.generate();
      await vm.rememberCurrent();
      await saveExample(_v2);
      await vm.generate();
      expect(vm.diff!.isEmpty, isFalse);
      await vm.rememberCurrent();
      expect(vm.diff!.isEmpty, isTrue);
      await vm.generate();
      expect(vm.diff!.isEmpty, isTrue);
      expect(vm.hasBaseline, isTrue);
    });

    test('the remembered version survives a new view model (it is in the settings table)', () async {
      final first = newViewModel();
      await first.generate();
      await first.rememberCurrent();
      await saveExample(_v2);
      final second = newViewModel();
      await second.generate();
      expect(second.hasBaseline, isTrue);
      expect(second.diff!.changes, isNotEmpty);
    });

    test('each collection has its own baseline', () async {
      final vm = newViewModel();
      await vm.generate();
      await vm.rememberCurrent();
      final other = await db.collectionRepository.createCollection('Other');
      final request = await addRequest(db, other, 'List things', url: '{{baseUrl}}/things');
      await db.exampleRepository.add(_example(request, '[{"id":1}]'));
      final second = newViewModel()..collectionId = other;
      await second.generate();
      expect(second.hasBaseline, isFalse);
      expect(second.diff, isNull);
    });

    test('a request body is a request: a new required field breaks, a response one does not', () {
      const before = ApiSpecRequest(
        name: 'Create user',
        method: 'POST',
        url: '{{baseUrl}}/users',
        bodyKind: ApiBodyKind.json,
        bodyText: '{"name":"Ann"}',
        exampleResponse: '{"id":3,"name":"Ann"}',
      );
      const after = ApiSpecRequest(
        name: 'Create user',
        method: 'POST',
        url: '{{baseUrl}}/users',
        bodyKind: ApiBodyKind.json,
        bodyText: '{"name":"Ann","age":3}',
        exampleResponse: '{"id":3,"name":"Ann","role":"admin"}',
      );
      const generator = ApiLayerGenerator();
      final diff = SchemaDiffer.diff(
        SchemaSnapshot.ofApiLayer(generator.generate('Shop', const [before])),
        SchemaSnapshot.ofApiLayer(generator.generate('Shop', const [after])),
      );
      final age = diff.changes.singleWhere((c) => c.field == 'age');
      expect((age.className, age.kind, age.breaking), ('CreateUserRequest', SchemaChangeKind.fieldAdded, true));
      final role = diff.changes.singleWhere((c) => c.field == 'role');
      expect((role.className, role.kind, role.breaking), ('CreateUserResponse', SchemaChangeKind.fieldAdded, false));
    });
  });

  group('the settings store', () {
    SchemaSnapshot snapshot() => SchemaSnapshot({
          'a.dart': const SchemaScope(SchemaRole.response, [SchemaClass('A', [SchemaField('x_y', 'xY', 'int', true)])]),
        });

    test('saves, loads, replaces and forgets, per source', () async {
      expect(await store.load('collection:1'), isNull);
      await store.save('collection:1', snapshot());
      await store.save('samples:user', SchemaSnapshot(const {}));
      final loaded = (await store.load('collection:1'))!;
      expect(SchemaDiffer.diff(snapshot(), loaded).isEmpty, isTrue);
      expect((await store.load('samples:user'))!.isEmpty, isTrue);
      await store.save('collection:1', SchemaSnapshot(const {}));
      expect((await store.load('collection:1'))!.isEmpty, isTrue);
      await store.forget('collection:1');
      expect(await store.load('collection:1'), isNull);
      expect(await store.load('samples:user'), isNotNull);
    });

    test('a damaged value is no baseline, not an error', () async {
      await settings.settingsDao.put('${SettingsModelSnapshotStore.keyPrefix}collection:9', '{not json');
      expect(await store.load('collection:9'), isNull);
    });

    test('keys name the source: a collection id, or the class name of pasted samples in lower case', () {
      expect(ModelSnapshotStore.collectionSource(12), 'collection:12');
      expect(ModelSnapshotStore.samplesSource('  UserResponse '), 'samples:userresponse');
    });

    test('nothing but names and types is written to the settings', () async {
      await db.exampleRepository.add(_example(listRequest, '[{"id":1,"name":"Ann Secret","token":"sk_live_abcdefghijklmnopqrstuv"}]'));
      db.examples.removeWhere((e) => e.requestId == listRequest && e.body == _v1);
      final vm = newViewModel();
      await vm.generate();
      await vm.rememberCurrent();
      final stored = (await settings.settingsDao.get('${SettingsModelSnapshotStore.keyPrefix}collection:$collection'))!;
      expect(stored, contains('token'));
      expect(stored, isNot(contains('sk_live')));
      expect(stored, isNot(contains('Ann Secret')));
    });
  });

  group('the panel', () {
    Future<void> pumpPanel(WidgetTester tester, SchemaDiff diff, {VoidCallback? onRemember}) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: ModelDiffPanel(diff: diff, onRemember: onRemember))),
        ));

    testWidgets('lists each change per class with a Breaking or Safe label and the advice', (tester) async {
      final diff = SchemaDiffer.diff(
        SchemaSnapshot({'u.dart': const SchemaScope(SchemaRole.response, [SchemaClass('User', [SchemaField('id', 'id', 'int', false), SchemaField('coupon', 'coupon', 'String', false)])])}),
        SchemaSnapshot({'u.dart': const SchemaScope(SchemaRole.response, [SchemaClass('User', [SchemaField('id', 'id', 'int', false), SchemaField('nick', 'nick', 'int', true)])])}),
      );
      var remembered = 0;
      await pumpPanel(tester, diff, onRemember: () => remembered++);
      expect(find.text('2 changes since the remembered version: 1 breaking, 1 non-breaking'), findsOneWidget);
      expect(find.text('User'), findsOneWidget);
      expect(find.text('Breaking'), findsOneWidget);
      expect(find.text('Safe'), findsOneWidget);
      expect(find.textContaining('Field removed: Field coupon (String) was removed.'), findsOneWidget);
      expect(find.textContaining('Delete every read or write of `.coupon`'), findsOneWidget);
      await tester.tap(find.text('Remember this version'));
      expect(remembered, 1);
      expect(find.text('Copy migration notes'), findsOneWidget);
    });

    testWidgets('an empty diff says the classes are the same', (tester) async {
      await pumpPanel(tester, const SchemaDiff([]));
      expect(find.text('The classes are the same as in the remembered version.'), findsOneWidget);
      expect(find.text('Copy migration notes'), findsNothing);
      expect(find.text('Remember this version'), findsNothing);
    });
  });

  group('the Collection to API layer tab', () {
    /// Real in-memory IO finishes outside the fake clock: alternate between letting it finish and letting the widgets react.
    Future<void> until(WidgetTester tester, bool Function() condition) async {
      for (var i = 0; i < 300 && !condition(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(condition(), isTrue, reason: 'timed out waiting');
    }

    Future<void> open(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      locator
        ..registerSingleton<ModelSnapshotStore>(store)
        ..registerFactory<ApiLayerViewModel>(() => ApiLayerViewModel(BuildApiLayerUseCase(db.loader, db.exampleRepository), store));
      final shell = ShellViewModel(db.requestRepository);
      final collections = CollectionsViewModel(db.collectionRepository, db.requestRepository);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final workplace = WorkplaceViewModel(repository: FakeWorkplaceRepository(canPickFolder: true), backupService: db.backupService, database: database, shellViewModel: shell);
      addTearDown(() async {
        collections.dispose();
        workplace.dispose();
        await database.close();
      });
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ShellViewModel>.value(value: shell),
          ChangeNotifierProvider<CollectionsViewModel>.value(value: collections),
          ChangeNotifierProvider<WorkplaceViewModel>.value(value: workplace),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(onPressed: () => DartStudioDialog.show(context, collectionId: collection, initialTab: 1), child: const Text('open')),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      testWidgets('generate, remember, change the example, generate again: the diff comes first (${size.width.toInt()}px)', (tester) async {
        await open(tester, size);
        await tester.tap(find.text('Generate'));
        await until(tester, () => find.text('api_client.dart').evaluate().isNotEmpty);
        expect(find.byKey(const ValueKey('model-diff-panel')), findsNothing, reason: 'nothing remembered yet');

        await tester.tap(find.text('Remember this version'));
        await until(tester, () => find.text('The classes are the same as in the remembered version.').evaluate().isNotEmpty);

        await saveExample(_v2);
        await tester.tap(find.text('Generate'));
        await until(tester, () => find.textContaining('breaking').evaluate().isNotEmpty);
        expect(find.byKey(const ValueKey('model-diff-panel')), findsOneWidget);
        expect(find.textContaining('3 changes since the remembered version: 2 breaking, 1 non-breaking'), findsOneWidget);
        // On a phone the panel scrolls: only the first rows are built.
        if (size.width > 800) {
          expect(find.text('Breaking'), findsNWidgets(2));
          expect(find.text('Safe'), findsOneWidget);
        }
        expect(find.text('Write changed files only…'), findsOneWidget);
        expect(find.text('Save to folder…'), findsOneWidget);
      });
    }
  });
}
