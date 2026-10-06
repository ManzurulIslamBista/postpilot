import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/defaults_chain.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/repositories/defaults_repository.dart';
import 'package:postpilot/features/defaults/presentation/defaults_dialog.dart';
import 'package:postpilot/features/defaults/presentation/view_models/defaults_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';

import '../support/in_memory_import_export_fakes.dart';

KeyValueItem _h(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

void main() {
  late InMemoryDb db;
  late int shop;
  late int orders;

  setUp(() async {
    await locator.reset();
    db = InMemoryDb();
    shop = await db.collectionRepository.createCollection('Shop');
    orders = await db.collectionRepository.createFolder(collectionId: shop, name: 'Orders');
    await db.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('X-Tenant', 'acme')]));
    await db.defaultsRepository.saveFolder(
      orders,
      LevelDefaults(headers: [_h('X-Api-Version', '2')], variables: [DefaultVariable(key: 'region', value: 'eu')]),
    );
  });

  tearDown(() => locator.reset());

  DefaultsViewModel viewModel() =>
      DefaultsViewModel(db.defaultsRepository, db.collectionAuthRepository, db.collectionVariableRepository);

  Future<void> open(WidgetTester tester, {int? folderId, DefaultsViewModel? vm}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => DefaultsDialog(collectionId: shop, folderId: folderId, viewModel: vm ?? viewModel()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('a folder', () {
    testWidgets('names the folder, shows what it sets and what it inherits, with where that comes from', (tester) async {
      await open(tester, folderId: orders);

      expect(find.text('Folder defaults'), findsOneWidget);
      expect(find.text('Shop  ›  Orders'), findsOneWidget);
      for (final tab in ['Headers', 'Auth', 'Variables', 'Tests']) {
        expect(find.text(tab), findsOneWidget, reason: tab);
      }
      expect(find.textContaining('replaces the one above'), findsOneWidget, reason: 'the help text states the override rule');
      expect(find.text('X-Api-Version'), findsOneWidget);
      expect(find.text('X-Tenant'), findsOneWidget, reason: 'inherited from the collection, read-only');
      expect(find.text('from collection "Shop"'), findsOneWidget);
    });

    testWidgets('Save is off until something changes, then writes the whole level and closes', (tester) async {
      await open(tester, folderId: orders);
      FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
      expect(save().onPressed, isNull);

      await tester.enterText(find.byType(TextFormField).at(1), '3');
      await tester.pump();
      expect(save().onPressed, isNotNull);
      expect(find.text('Not saved yet.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Folder defaults'), findsNothing, reason: 'the dialog closed');
      final saved = db.folderDefaults[orders]!;
      expect(saved.headers.single.value, '3');
      expect(saved.variables.single.key, 'region', reason: 'the other tabs were written with it, unchanged');
      expect(find.text('Folder defaults saved'), findsOneWidget);
    });

    testWidgets('closing with edits asks first; keeping them keeps the dialog, discarding closes it without saving', (tester) async {
      await open(tester, folderId: orders);
      await tester.enterText(find.byType(TextFormField).at(1), '9');
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Folder defaults'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Folder defaults'), findsNothing);
      expect(db.folderDefaults[orders]!.headers.single.value, '2', reason: 'nothing was written');
    });

    testWidgets('closing without edits just closes', (tester) async {
      await open(tester, folderId: orders);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Folder defaults'), findsNothing);
    });

    testWidgets('its Auth tab offers "Inherit from parent" and picking another auth stores it on the folder', (tester) async {
      await open(tester, folderId: orders);
      await tester.tap(find.text('Auth'));
      await tester.pumpAndSettle();
      expect(find.text('Inherit from parent'), findsWidgets, reason: 'a folder can leave the auth to the levels above');

      await tester.tap(find.byType(DropdownButton<AuthType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bearer Token').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Token'), 'folder-token');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final auth = db.folderDefaults[orders]!.auth!;
      expect(auth.type, AuthType.bearer);
      expect(auth.bearerToken, 'folder-token');
    });

    testWidgets('its Variables tab adds a secret variable whose value is hidden', (tester) async {
      await open(tester, folderId: orders);
      await tester.tap(find.text('Variables'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add variable'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Name').last, 'tenantKey');
      await tester.enterText(find.widgetWithText(TextFormField, 'Value').last, 'hush');
      await tester.tap(find.byIcon(Icons.lock_open).last);
      await tester.pumpAndSettle();
      expect(tester.widgetList<TextField>(find.byType(TextField)).last.obscureText, isTrue, reason: 'the new row\'s value');
      expect(tester.widgetList<TextField>(find.byType(TextField)).first.obscureText, isFalse);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(db.folderDefaults[orders]!.variables.map((v) => (v.key, v.value, v.isSecret)), [('region', 'eu', false), ('tenantKey', 'hush', true)]);
    });

    testWidgets('a variable name the resolver could not match is flagged', (tester) async {
      await open(tester, folderId: orders);
      await tester.tap(find.text('Variables'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add variable'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Name').last, 'bad name!');
      await tester.pump();

      expect(find.textContaining('Use letters, digits'), findsOneWidget);
    });

    testWidgets('its Tests tab lists what it inherits and lets assertions be added', (tester) async {
      await open(tester, folderId: orders);
      await tester.tap(find.text('Tests'));
      await tester.pumpAndSettle();
      expect(find.text('Assertions'), findsOneWidget);

      await tester.tap(find.text('Add assertion'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(db.folderDefaults[orders]!.assertions, hasLength(1));
    });
  });

  group('a collection', () {
    testWidgets('names the collection and has no "Inherit from parent" for its auth', (tester) async {
      await open(tester);

      expect(find.text('Collection defaults'), findsOneWidget);
      expect(find.text('Shop'), findsOneWidget);

      await tester.tap(find.text('Auth'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<AuthType>));
      await tester.pumpAndSettle();
      expect(find.text('Inherit from parent'), findsNothing);
    });

    testWidgets('its Variables tab edits the collection variables themselves, saved with the rest', (tester) async {
      await db.collectionVariableRepository
          .upsert(CollectionVariableEntity(id: 0, collectionId: shop, key: 'baseUrl', value: 'https://shop.test', enabled: true));
      await db.collectionVariableRepository
          .upsert(CollectionVariableEntity(id: 0, collectionId: shop, key: 'old', value: 'x', enabled: true));
      await open(tester);
      await tester.tap(find.text('Variables'));
      await tester.pumpAndSettle();
      expect(find.text('baseUrl'), findsOneWidget);
      expect(find.byIcon(Icons.lock_open), findsNothing, reason: 'collection variables have no secret flag');

      await tester.enterText(find.widgetWithText(TextFormField, 'baseUrl'), 'apiUrl');
      await tester.pump(); // a frame between two edits, as there always is between a person's
      await tester.tap(find.byTooltip('Remove').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(db.variables.map((v) => (v.key, v.value)), [('apiUrl', 'https://shop.test')]);
    });

    testWidgets('saving writes its headers and tests, and its auth only when it changed', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextFormField).at(1), 'globex');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(db.collectionDefaults[shop]!.headers.single.value, 'globex');
      expect(db.collectionAuth, isEmpty, reason: 'a collection that never had an auth keeps none');
    });

    testWidgets('a collection auth chosen here is stored in collection_auth', (tester) async {
      await open(tester);
      await tester.tap(find.text('Auth'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<AuthType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bearer Token').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Token'), 'collection-token');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final stored = RequestAuth.fromJsonString(db.collectionAuth[shop]);
      expect(stored?.type, AuthType.bearer);
      expect(stored?.bearerToken, 'collection-token');
    });
  });

  testWidgets('a level that cannot be read says so instead of showing an empty editor', (tester) async {
    final vm = DefaultsViewModel(_Failing(), db.collectionAuthRepository, db.collectionVariableRepository);
    await open(tester, vm: vm);

    expect(find.textContaining('Could not read the defaults'), findsOneWidget);
  });
}

final class _Failing implements DefaultsRepository {
  @override
  Future<DefaultsTree> loadTree(int collectionId) => throw StateError('disk on fire');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
