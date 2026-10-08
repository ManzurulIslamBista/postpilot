// The matrix run dialog and its grid, opened for real in a light and a dark theme on a desktop and a phone screen:
// the setup, picking columns, running (against a scripted runner), the grid with its differences and expectations, a
// cell's diff, the identity editor, the exports and Stop. Flutter turns a layout overflow or a missing provider into a
// test failure, so this is what shows the screens are usable.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/widgets/tool_dialog.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/collections/presentation/view_models/collection_runner_view_model.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_column.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_grid.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_identity.dart';
import 'package:postpilot/features/matrix_run/domain/repositories/matrix_identity_store.dart';
import 'package:postpilot/features/matrix_run/domain/services/matrix_analysis.dart';
import 'package:postpilot/features/matrix_run/domain/services/matrix_run_service.dart';
import 'package:postpilot/features/matrix_run/presentation/matrix_grid_view.dart';
import 'package:postpilot/features/matrix_run/presentation/matrix_run_dialog.dart';
import 'package:postpilot/features/matrix_run/presentation/matrix_run_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_report.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/services/run_data_parser.dart';
import 'package:postpilot/features/request_builder/domain/services/run_selection.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:postpilot/core/network/api_client.dart';

// ---------------------------------------------------------------- fakes

final _requests = <RequestSummaryEntity>[
  const RequestSummaryEntity(id: 1, folderId: 10, name: 'List orders', method: HttpMethod.get, orderIndex: 1),
  const RequestSummaryEntity(id: 2, folderId: null, name: 'Get me', method: HttpMethod.get, orderIndex: 2),
  const RequestSummaryEntity(id: 3, folderId: null, name: 'Create order', method: HttpMethod.post, orderIndex: 3),
];

final class _Requests implements RequestRepository {
  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => Stream.value(_requests);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _Collections implements CollectionRepository {
  @override
  Stream<List<CollectionEntity>> watchCollections() => Stream.value(const [CollectionEntity(id: 1, name: 'Shop'), CollectionEntity(id: 2, name: 'Empty')]);

  @override
  Stream<List<FolderEntity>> watchFolders(int collectionId) =>
      Stream.value(const [FolderEntity(id: 10, collectionId: 1, parentFolderId: null, name: 'Orders')]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _Environments implements EnvironmentRepository {
  @override
  Stream<List<EnvironmentEntity>> watchAll() => Stream.value(const [
        EnvironmentEntity(id: 1, name: 'Dev', isActive: false),
        EnvironmentEntity(id: 2, name: 'Staging', isActive: true),
        EnvironmentEntity(id: 3, name: 'Production', isActive: false),
      ]);

  @override
  Stream<EnvironmentEntity?> watchActive() => Stream.value(const EnvironmentEntity(id: 2, name: 'Staging', isActive: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _NoHistory implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoAuth implements CollectionAuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoVariables implements CollectionVariableRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoEnvironment implements EnvironmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Globals implements GlobalVariableRepository {
  @override
  Stream<List<GlobalVariableEntity>> watchAll() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoScripts implements RequestScriptsRepository {
  @override
  Future<RequestScriptsEntity?> get(int requestId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoNetwork implements ApiClient {
  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async => throw StateError('the picker never sends');
}

final class _MemoryIdentities implements MatrixIdentityStore {
  List<MatrixIdentity> saved = const [];

  @override
  Future<List<MatrixIdentity>> load() async => saved;

  @override
  Future<void> save(List<MatrixIdentity> identities) async => saved = identities;
}

MatrixCell _answer(int status, String body, [int ms = 20]) => MatrixCell.text(status: status, duration: Duration(milliseconds: ms), body: body);

/// Answers like a server that lets Production deny `/me`; the rows are the requests the spec selects.
final class _FakeRunner implements MatrixRunner {
  MatrixRunSpec? spec;
  Completer<void>? gate;
  ApiCancelToken? token;
  bool? confirmedProduction;
  bool askProduction = false;
  MatrixCell Function(String request, MatrixColumn column, int n) cellFor = (request, column, n) {
    if (request == 'Get me' && (column.environment == 'Production' || (column.identity?.isAnonymous ?? false))) {
      return _answer(403, '{"error":"forbidden"}', 31);
    }
    return _answer(200, '{"items":[1,2],"id":$n}', 20 + n);
  };

  @override
  Future<MatrixRunResult> run(MatrixRunSpec spec, {ApiCancelToken? cancelToken, ProductionConfirm? confirm, MatrixProgress? onProgress}) async {
    this.spec = spec;
    token = cancelToken;
    final ids = (spec.selection as RunRequests).requestIds;
    final picked = [for (final r in _requests) if (ids.contains(r.id) && (!spec.readOnlyOnly || r.method == HttpMethod.get)) r];
    final grid = MatrixGrid(spec.columns, [
      for (final r in picked) MatrixRow(key: MatrixRunService.rowKey(r.id), name: r.name, method: r.method.label, folder: r.folderId == null ? '' : 'Orders', columns: spec.columns.length),
    ]);
    final notes = <String, String>{};
    var n = 0;
    for (final (index, column) in spec.columns.indexed) {
      if (askProduction && column.environment == 'Production' && confirm != null) {
        confirmedProduction = await confirm(const ProductionWarning('Production', 'Running "Shop" sends 1 data-changing request'));
        if (confirmedProduction != true) {
          notes[column.key] = 'Not sent: the production confirmation for Production was declined.';
          for (final row in grid.rows) {
            row.cells[index] = MatrixCell.notSent(notes[column.key]!);
          }
          continue;
        }
      }
      onProgress?.call(grid, notes, index);
      final hold = gate;
      if (hold != null) await hold.future;
      if (cancelToken?.isCancelled ?? false) return MatrixRunResult(grid, notes, 0, true);
      for (final row in grid.rows) {
        grid.setCell(row.key, index, cellFor(row.name, column, ++n));
        onProgress?.call(grid, notes, index);
      }
    }
    return MatrixRunResult(grid, notes, spec.readOnlyOnly ? 1 : 0, false);
  }
}

// ---------------------------------------------------------------- harness

void main() {
  late _FakeRunner runner;
  late _MemoryIdentities identities;
  late MatrixRunViewModel vm;
  String? clipboard;

  setUp(() {
    runner = _FakeRunner();
    identities = _MemoryIdentities();
    final resolver = BuildVariableResolverUseCase(_NoVariables(), _NoEnvironment(), _Globals());
    final send = SendRequestUseCase(_NoNetwork(), resolver, _NoHistory(), _NoAuth());
    final scripts = RunRequestScriptsUseCase(_NoScripts(), resolver, _NoEnvironment(), _Globals());
    final service = CollectionRunnerService.withFolders(_Requests(), send, scripts, _Collections());
    var ids = 0;
    vm = MatrixRunViewModel(
      runner: runner,
      identities: identities,
      environments: _Environments(),
      collections: _Collections(),
      picker: CollectionRunnerViewModel(
        service,
        const RunDataParser(),
        const CollectionRunExporter(),
        ({required String fileName, required Uint8List bytes, required String mimeType}) async => null,
      ),
      download: ({required String fileName, required Uint8List bytes, required String mimeType}) async => '/tmp/$fileName',
      isProduction: (name) => name == 'Production',
      newId: () => 'id${ids++}',
    );
    clipboard = null;
  });

  tearDown(() async => locator.reset());

  Future<void> open(WidgetTester tester, {required Size size, bool dark = false, Future<bool> Function(ProductionWarning)? confirm}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => ToolDialog.show<void>(context, (_) => MatrixRunDialog(viewModel: vm, collectionId: 1, confirm: confirm)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tick(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(FilterChip, label);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> tapIt(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> runMatrix(WidgetTester tester) async {
    final run = find.widgetWithText(FilledButton, 'Run matrix');
    await tester.ensureVisible(run);
    await tester.tap(run);
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

      group('($label)', () {
        testWidgets('the setup lists the collection, its requests, the environments and the options, read-only on', (tester) async {
          await open(tester, size: size, dark: dark);

          expect(find.text('Matrix run'), findsOneWidget);
          expect(find.text('Shop: compare environments or users'), findsOneWidget);
          expect(find.text('List orders'), findsOneWidget);
          expect(find.text('Create order'), findsOneWidget);
          expect(find.widgetWithText(FilterChip, 'Dev'), findsOneWidget);
          expect(find.widgetWithText(FilterChip, 'Production'), findsOneWidget);
          expect(find.byIcon(Icons.shield_outlined), findsOneWidget, reason: 'only Production looks like production');
          expect(find.text('Read-only requests only (recommended)'), findsOneWidget);
          expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
          expect(find.textContaining('1 selected request changes data and will be left out.'), findsOneWidget);
          expect(find.textContaining('Tick at least two columns'), findsWidgets, reason: 'in the footer and in the banner');
          expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Run matrix')).onPressed, isNull);
          expect(tester.takeException(), isNull);
        });

        testWidgets('two environments are enough to run; the grid shows who differs, and a cell opens its diff', (tester) async {
          await open(tester, size: size, dark: dark);
          await tick(tester, 'Dev');
          await tick(tester, 'Production');
          expect(find.text('2 columns × 2 requests = 4 requests will really be sent.'), findsOneWidget);

          await runMatrix(tester);

          final spec = runner.spec!;
          expect(spec.columns.map((c) => c.label), ['Dev', 'Production']);
          expect(spec.readOnlyOnly, isTrue);
          expect((spec.selection as RunRequests).requestIds, {1, 2, 3});
          expect(find.text('1 of 2 requests differ'), findsOneWidget);
          expect(find.text('1 left out (changes data)'), findsOneWidget);
          expect(find.text('DIFFERS'), findsOneWidget);
          expect(find.text('403'), findsOneWidget);
          expect(find.text('200'), findsNWidgets(3));
          expect(find.textContaining('status 200 vs 403'), findsWidgets);
          expect(find.textContaining('reference'), findsOneWidget);

          await tester.ensureVisible(find.text('403'));
          await tester.tap(find.text('403'));
          await tester.pumpAndSettle();
          expect(find.text('GET Get me'), findsOneWidget);
          expect(find.text('Production against Dev'), findsOneWidget);
          expect(find.textContaining('status 200 vs 403'), findsWidgets);
          expect(find.text('Dev: 200 · 22 ms'), findsOneWidget);
          expect(find.text('Production: 403 · 31 ms'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(find.byTooltip('Close').last);
          await tester.pumpAndSettle();
          expect(find.text('GET Get me'), findsNothing);
          expect(tester.takeException(), isNull);
        });

        testWidgets('an expectation set on a column marks the cells that are not what was expected', (tester) async {
          await open(tester, size: size, dark: dark);
          await tick(tester, 'Dev');
          await tick(tester, 'Production');
          await runMatrix(tester);
          expect(find.text('Unexpected access'), findsNothing);

          // "Production must be denied everywhere": its List orders answered 200.
          final menu = find.byTooltip('What is expected of Production');
          await tester.ensureVisible(menu);
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Expect denial on every request'));
          await tester.pumpAndSettle();

          expect(find.text('1 unexpected'), findsOneWidget);
          expect(find.text('Unexpected access'), findsOneWidget);
          expect(vm.analysis!.unexpectedCells, 1);
          expect(vm.expectationOf('r1', MatrixColumn(environment: 'Production').key), MatrixExpect.deny);
          expect(tester.takeException(), isNull);
        });
      });
    }
  }

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      testWidgets('identities: "Add anonymous" opens the editor with a cleared token, hides secret values, and saves on this device (${dark ? 'dark' : 'light'} ${size.width.toInt()}px)', (tester) async {
        await open(tester, size: size, dark: dark);
        await tapIt(tester, find.text('Add anonymous'));

        expect(find.text('New identity'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'anonymous'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'token'), findsWidgets, reason: 'the Variable field holds it (and shows it as a hint)');
        // A credential's value is hidden until asked for.
        final value = tester.widget<TextField>(find.widgetWithText(TextField, 'Value'));
        expect(value.obscureText, isTrue);
        await tester.enterText(find.widgetWithText(TextField, 'Value'), 'abc123');
        await tester.tap(find.byTooltip('Show the value'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Value')).obscureText, isFalse);
        expect(find.textContaining('never written to the workspace file'), findsOneWidget);

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilterChip, 'anonymous'), findsOneWidget);
        expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'anonymous')).selected, isTrue);
        expect(identities.saved.single.name, 'anonymous');
        expect(identities.saved.single.variables, {'token': 'abc123'});
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('expectations set on the columns before the run mark what the run got that was not expected', (tester) async {
    identities.saved = const [
      MatrixIdentity(id: 'a', name: 'admin', variables: {'token': 'tok'}),
      MatrixIdentity(id: 'n', name: 'anonymous', variables: {'token': ''}),
    ];
    await open(tester, size: const Size(420, 800));
    await tick(tester, 'admin');
    await tick(tester, 'anonymous');
    expect(find.text('Expected results (optional)'), findsOneWidget);
    expect(find.text('anonymous: any'), findsOneWidget);

    await tapIt(tester, find.byTooltip('What is expected of anonymous'));
    await tester.tap(find.text('Expect denial'));
    await tester.pumpAndSettle();
    await tapIt(tester, find.byTooltip('What is expected of admin'));
    await tester.tap(find.text('Expect access'));
    await tester.pumpAndSettle();
    expect(find.text('anonymous: denied'), findsOneWidget);
    expect(find.text('admin: access'), findsOneWidget);

    await runMatrix(tester);
    // Anonymous is denied on Get me, as expected, but List orders let it in: one unexpected access, none for admin.
    expect(find.text('1 unexpected'), findsOneWidget);
    expect(find.text('Unexpected access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('an expectation on one request beats the one on its column, and setting the column again replaces them', () {
    const key = 'anonymous|n';
    vm.setColumnExpectation(key, MatrixExpect.deny);
    expect(vm.expectationOf('r1', key), MatrixExpect.deny);
    expect(vm.expectationOf('r2', key), MatrixExpect.deny);

    vm.setExpectation('r1', key, MatrixExpect.allow);
    expect(vm.expectationOf('r1', key), MatrixExpect.allow);
    expect(vm.expectationOf('r2', key), MatrixExpect.deny);

    vm.setExpectation('r2', key, MatrixExpect.none);
    expect(vm.expectationOf('r2', key), MatrixExpect.none, reason: 'no expectation is an answer too: it beats the column');

    vm.setColumnExpectation(key, MatrixExpect.allow);
    expect(vm.expectationOf('r1', key), MatrixExpect.allow);
    expect(vm.expectationOf('r2', key), MatrixExpect.allow, reason: 'the column replaces what was set on single requests');
    vm.setColumnExpectation(key, MatrixExpect.none);
    expect(vm.expectationOf('r1', key), MatrixExpect.none);
    expect(vm.columnExpectationOf(key), MatrixExpect.none);
  });

  testWidgets('an identity needs a name and a variable; an existing one can be edited and deleted', (tester) async {
    identities.saved = const [MatrixIdentity(id: 'a', name: 'admin', variables: {'token': 'tok'})];
    await open(tester, size: const Size(1200, 900));
    expect(find.widgetWithText(FilterChip, 'admin'), findsOneWidget);

    await tapIt(tester, find.text('Add identity'));
    expect(find.text('Give the identity a name.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'user');
    await tester.pump();
    expect(find.text('Add at least one variable.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'user'), findsNothing);

    await tapIt(tester, find.byTooltip('Edit admin'));
    expect(find.text('Edit identity'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'admin'), findsNothing);
    expect(identities.saved, isEmpty);
  });

  testWidgets('identity columns: environments times identities, in the order of the chips', (tester) async {
    identities.saved = const [
      MatrixIdentity(id: 'a', name: 'admin', variables: {'token': 'tok'}),
      MatrixIdentity(id: 'n', name: 'anonymous', variables: {'token': ''}),
    ];
    await open(tester, size: const Size(1200, 900));
    await tick(tester, 'admin');
    await tick(tester, 'anonymous');
    expect(find.textContaining('2 columns: admin, anonymous'), findsOneWidget);
    await tick(tester, 'Dev');
    await tick(tester, 'Staging');
    expect(find.textContaining('4 columns: Dev · admin, Dev · anonymous, Staging · admin, Staging · anonymous'), findsOneWidget);

    await runMatrix(tester);
    expect(runner.spec!.columns.map((c) => c.label), ['Dev · admin', 'Dev · anonymous', 'Staging · admin', 'Staging · anonymous']);
    // anonymous is denied on Get me, in both environments.
    expect(find.text('403'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('more than eight columns are refused with the reason', (tester) async {
    identities.saved = [for (var i = 0; i < 4; i++) MatrixIdentity(id: 'i$i', name: 'user$i', variables: const {'token': 'x'})];
    await open(tester, size: const Size(1200, 900));
    for (var i = 0; i < 4; i++) {
      await tick(tester, 'user$i');
    }
    await tick(tester, 'Dev');
    await tick(tester, 'Staging');
    await tick(tester, 'Production');
    expect(find.textContaining('That makes 12 columns; the most is 8'), findsWidgets);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Run matrix')).onPressed, isNull);
  });

  testWidgets('read-only off lists every request again and sends the selection as ticked', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await tapIt(tester, find.byType(SwitchListTile));
    expect(find.textContaining('will be left out'), findsNothing);
    await tick(tester, 'Dev');
    await tick(tester, 'Staging');
    expect(find.text('2 columns × 3 requests = 6 requests will really be sent.'), findsOneWidget);
    await runMatrix(tester);
    expect(runner.spec!.readOnlyOnly, isFalse);
    expect(vm.grid!.rows.map((r) => r.method), ['GET', 'GET', 'POST']);
  });

  testWidgets('ticking only a write while read-only says why nothing can run', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await tester.tap(find.text('Select none'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create order'));
    await tester.pumpAndSettle();
    await tick(tester, 'Dev');
    await tick(tester, 'Staging');
    expect(find.textContaining('Only data-changing requests are ticked'), findsWidgets);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Run matrix')).onPressed, isNull);
  });

  testWidgets('copy puts the Markdown or the CSV of the grid on the clipboard; both show the expectations', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await tick(tester, 'Dev');
    await tick(tester, 'Production');
    await runMatrix(tester);

    await tester.tap(find.text('Copy Markdown'));
    await tester.pumpAndSettle();
    expect(clipboard, startsWith('## Shop: matrix run\n\nCompared: structure and values. Columns: Dev, Production;'));
    expect(clipboard, contains('| Request | Dev | Production | Result |'));
    expect(clipboard, contains('DIFFERS: Production: status 200 vs 403'));
    expect(find.text('Markdown copied'), findsOneWidget);

    await tester.tap(find.text('Copy CSV'));
    await tester.pumpAndSettle();
    expect(clipboard, startsWith('request,method,folder,Dev status,Dev ms,Dev body,Production status,Production ms,Production body,differs,differences,unexpected\n'));
    expect(clipboard, contains('Get me,GET,,200,'));
    // No response body, header or token reaches an export.
    expect(clipboard, isNot(contains('forbidden')));
  });

  testWidgets('the save menu writes the file and says where', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await tick(tester, 'Dev');
    await tick(tester, 'Staging');
    await runMatrix(tester);
    await tester.tap(find.byTooltip('Save the grid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as CSV'));
    await tester.pumpAndSettle();
    expect(find.text('Saved to /tmp/matrix-run.csv'), findsOneWidget);
  });

  testWidgets('the compare mode can be switched on the results; structure only ignores different data', (tester) async {
    runner.cellFor = (request, column, n) => _answer(200, '{"items":[{"name":"${column.label}"}]}');
    await open(tester, size: const Size(1200, 900));
    await tick(tester, 'Dev');
    await tick(tester, 'Staging');
    await runMatrix(tester);
    expect(find.text('2 of 2 requests differ'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Structure only'));
    await tester.pumpAndSettle();
    expect(find.text('No differences'), findsOneWidget);
    expect(find.text('DIFFERS'), findsNothing);
  });

  testWidgets('a production column that would change data asks through the dialog, and a "no" is passed on', (tester) async {
    runner.askProduction = true;
    final asked = <String>[];
    await open(tester, size: const Size(1200, 900), confirm: (w) async {
      asked.add('${w.environmentName}: ${w.description}');
      return false;
    });
    await tick(tester, 'Dev');
    await tick(tester, 'Production');
    await runMatrix(tester);
    expect(asked, ['Production: Running "Shop" sends 1 data-changing request']);
    expect(runner.confirmedProduction, isFalse);
    expect(find.textContaining('Production: Not sent: the production confirmation for Production was declined.'), findsOneWidget);
    expect(find.text('not sent'), findsWidgets);
  });

  testWidgets('without a test hook the production lock\'s own dialog is shown', (tester) async {
    runner.askProduction = true;
    await open(tester, size: const Size(1200, 900));
    await tick(tester, 'Dev');
    await tick(tester, 'Production');
    await tester.tap(find.widgetWithText(FilledButton, 'Run matrix'));
    // The run is waiting for the answer, with its progress bar going: pump by hand, it never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Send to Production?'), findsOneWidget);
    await tester.tap(find.text('Send anyway'));
    await tester.pumpAndSettle();
    expect(runner.confirmedProduction, isTrue);
    expect(find.text('Send to Production?'), findsNothing);
    expect(find.text('1 of 2 requests differ'), findsOneWidget);
  });

  testWidgets('Stop ends a run that is waiting; the button keeps its label and shows a spinner while it runs', (tester) async {
    runner.gate = Completer<void>();
    await open(tester, size: const Size(1200, 900));
    await tick(tester, 'Dev');
    await tick(tester, 'Staging');
    await tester.tap(find.widgetWithText(FilledButton, 'Run matrix'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Running…'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Running Dev (1 of 2)…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Running…')).onPressed, isNull);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(runner.token!.isCancelled, isTrue);
    runner.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Stopped.'), findsOneWidget);
    expect(find.text('Run again'), findsOneWidget);
  });

  testWidgets('Edit setup goes back and View results returns to the grid', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await tick(tester, 'Dev');
    await tick(tester, 'Staging');
    await runMatrix(tester);
    await tester.tap(find.text('Edit setup'));
    await tester.pumpAndSettle();
    expect(find.text('Read-only requests only (recommended)'), findsOneWidget);
    await tester.tap(find.text('View results'));
    await tester.pumpAndSettle();
    expect(find.textContaining('reference'), findsOneWidget);
  });

  group('the grid on its own', () {
    for (final dark in [false, true]) {
      for (final width in [1200.0, 420.0]) {
        testWidgets('eight columns and many rows scroll instead of overflowing, ${dark ? 'dark' : 'light'} ${width.toInt()}px', (tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final columns = [for (var i = 0; i < 8; i++) MatrixColumn(environment: 'Environment number $i')];
          final grid = MatrixGrid(columns, [
            for (var r = 0; r < 40; r++) MatrixRow(key: 'r$r', name: 'A request with quite a long name number $r', method: r.isEven ? 'GET' : 'DELETE', folder: 'Some / Nested / Folder', columns: 8),
          ]);
          for (final row in grid.rows) {
            for (var c = 0; c < 8; c++) {
              row.cells[c] = switch ((row.key.hashCode + c) % 4) {
                0 => _answer(200, '{"a":$c}'),
                1 => _answer(503, '{"error":"unavailable, please try again later"}'),
                2 => const MatrixCell.failed('The URL still contains {{host}}: pass --env or --var host=...'),
                _ => const MatrixCell.notSent('Run if did not hold'),
              };
            }
          }
          grid.rows.first.cells[3] = null;
          final analysis = MatrixAnalysis.of(grid, expectations: {
            'r1': {columns[1].key: MatrixExpect.allow, columns[2].key: MatrixExpect.deny},
          });
          await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: MatrixGridView(analysis: analysis, runningColumn: 3, onOpenCell: (_, _) {}, onExpect: (_, _, _) {}, onExpectColumn: (_, _) {}),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('Environment number 0'), findsOneWidget);
          await tester.drag(find.textContaining('name number 0').first, const Offset(0, -2000));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
