// "Clean up what this request creates" in the Settings tab: the section on its own, and inside the real tab with the
// real view model, where the setting is saved together with the request's other settings and nothing is overwritten.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/auth_renewal/domain/services/relogin_policy.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_settings.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/view_models/cleanup_section_view_model.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/widgets/cleanup_section.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/settings/presentation/view_models/request_settings_view_model.dart';
import 'package:postpilot/features/settings/presentation/widgets/request_settings_tab.dart';
import '../settings/fakes/fake_settings_repositories.dart';
import 'cleanup_support.dart';

CleanupSectionViewModel _vm(ApiRequestEntity request, {List<String> others = const [], ApiResponseEntity? last}) => CleanupSectionViewModel(
      findRequest: (id) async => request,
      candidates: (collectionId) async => [
        ReloginCandidate(
          folderPath: '',
          name: request.name,
          method: request.method,
          value: RequestSummaryEntity(id: request.id, folderId: null, name: request.name, method: request.method),
        ),
        for (final (i, path) in others.indexed)
          ReloginCandidate(
            folderPath: path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '',
            name: path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path,
            method: HttpMethod.delete,
            value: RequestSummaryEntity(id: 100 + i, folderId: null, name: path, method: HttpMethod.delete),
          ),
      ],
      lastResponse: (_) => last,
    );

ApiResponseEntity _answer(Object? json, {int status = 200}) => ApiResponseEntity(
      statusCode: status,
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(json))),
      duration: const Duration(milliseconds: 5),
    );

/// Holds the setting the way the Settings tab does, so a change comes back down as the widget's new value.
final class _Host extends StatefulWidget {
  final CleanupSectionViewModel vm;
  final CleanupSettings initial;
  final List<CleanupSettings> changes;
  const _Host({super.key, required this.vm, required this.initial, required this.changes});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late CleanupSettings cleanup = widget.initial;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: CleanupSection(
          requestId: 7,
          viewModel: widget.vm,
          cleanup: cleanup,
          onChanged: (next) {
            widget.changes.add(next);
            setState(() => cleanup = next);
          },
        ),
      );
}

Future<List<CleanupSettings>> _pump(
  WidgetTester tester,
  CleanupSectionViewModel vm, {
  CleanupSettings initial = CleanupSettings.none,
  double width = 900,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final changes = <CleanupSettings>[];
  await tester.pumpWidget(MaterialApp(theme: theme ?? AppTheme.light, home: Scaffold(body: _Host(key: UniqueKey(), vm: vm, initial: initial, changes: changes))));
  await tester.pumpAndSettle();
  return changes;
}

Finder _switch() => find.descendant(of: find.byKey(const ValueKey('cleanup-section')), matching: find.byType(Switch));

void main() {
  tearDown(() => locator.reset());

  group('the section', () {
    for (final (themeName, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      for (final width in [1200.0, 420.0]) {
        testWidgets('is complete and does not overflow, $themeName, ${width.toInt()} px wide', (tester) async {
          const settings = CleanupSettings(enabled: true, idPath: 'data.id', undo: CleanupUndo.request, request: 'Partners/Delete a partner with a very long name indeed');
          await _pump(tester, _vm(odooCreate(), others: ['Partners/Delete a partner with a very long name indeed', 'Health']), initial: settings, width: width, theme: theme);

          expect(find.text('Clean up what this request creates'), findsOneWidget);
          expect(find.text('Where is the created id?'), findsOneWidget);
          expect(find.text('How is it undone?'), findsOneWidget);
          for (final label in ['Find it automatically', 'At this JSON path', 'Automatic', 'Odoo unlink', 'REST DELETE', 'Another request']) {
            expect(find.text(label), findsOneWidget, reason: label);
          }
          expect(find.widgetWithText(TextField, 'JSON path of the id'), findsOneWidget);
          expect(find.text('Request that deletes it'), findsOneWidget);
          expect(find.textContaining('Kept until you close PostPilot'), findsOneWidget);
          expect(find.textContaining('{{created.id}}'), findsWidgets);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('off, it is a header with one line, and a switch turns it on without losing what was set up', (tester) async {
      final changes = await _pump(tester, _vm(createRequest()), initial: const CleanupSettings(idPath: 'data.id', undo: CleanupUndo.restDelete));

      expect(find.text('Delete the records this request creates when a run is done'), findsOneWidget);
      expect(find.text('Where is the created id?'), findsNothing);
      await tester.tap(_switch());
      await tester.pumpAndSettle();

      expect(changes.single, const CleanupSettings(enabled: true, idPath: 'data.id', undo: CleanupUndo.restDelete));
      expect(find.text('Where is the created id?'), findsOneWidget);
      expect(find.text('id at data.id, undone by rest delete'), findsOneWidget);
    });

    testWidgets('an Odoo create gets a banner that switches cleanup on with unlink in one click', (tester) async {
      final changes = await _pump(tester, _vm(odooCreate()));

      expect(find.text('Odoo create detected: delete with unlink'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cleanup-use-suggestion')));
      await tester.pumpAndSettle();

      expect(changes.single, const CleanupSettings(enabled: true, undo: CleanupUndo.odooUnlink));
      expect(find.byKey(const ValueKey('cleanup-suggestion')), findsNothing, reason: 'once adopted, it is not offered again');
      expect(find.text('Odoo unlink'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('cleanup-undo-odooUnlink'))).selected, isTrue);
    });

    testWidgets('a POST whose last answer held an id gets the REST proposal, with the path when it is not id', (tester) async {
      final changes = await _pump(tester, _vm(createRequest(), last: _answer({'data': {'id': 4}})));

      expect(find.textContaining('REST create detected (id in `data.id`)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cleanup-use-suggestion')));
      await tester.pumpAndSettle();

      expect(changes.single, const CleanupSettings(enabled: true, undo: CleanupUndo.restDelete, idPath: 'data.id'));
      expect(find.widgetWithText(TextField, 'JSON path of the id'), findsOneWidget, reason: 'the path mode follows the proposal');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'JSON path of the id')).controller!.text, 'data.id');
    });

    testWidgets('a GET, or a POST that has not answered yet, is not offered anything', (tester) async {
      await _pump(tester, _vm(createRequest(method: HttpMethod.get), last: _answer({'id': 4})));
      expect(find.byKey(const ValueKey('cleanup-suggestion')), findsNothing);
      await _pump(tester, _vm(createRequest()));
      expect(find.byKey(const ValueKey('cleanup-suggestion')), findsNothing);
    });

    testWidgets('the id can be named by a path, and going back to automatic forgets it', (tester) async {
      final changes = await _pump(tester, _vm(createRequest()), initial: const CleanupSettings(enabled: true));

      expect(find.widgetWithText(TextField, 'JSON path of the id'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('cleanup-id-path')));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'JSON path of the id'), r'$.result[0].id');
      await tester.pump();
      expect(changes.last.idPath, r'$.result[0].id');

      await tester.tap(find.byKey(const ValueKey('cleanup-id-auto')));
      await tester.pumpAndSettle();
      expect(changes.last.idPath, '');
      expect(find.widgetWithText(TextField, 'JSON path of the id'), findsNothing);
    });

    testWidgets('each way to undo can be chosen, and the hint under it says what it does', (tester) async {
      final changes = await _pump(tester, _vm(createRequest()), initial: const CleanupSettings(enabled: true));

      await tester.tap(find.byKey(const ValueKey('cleanup-undo-odooUnlink')));
      await tester.pumpAndSettle();
      expect(changes.last.undo, CleanupUndo.odooUnlink);
      expect(find.textContaining('Sends unlink with the created ids'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cleanup-undo-restDelete')));
      await tester.pumpAndSettle();
      expect(changes.last.undo, CleanupUndo.restDelete);
      expect(find.textContaining('Sends DELETE <this URL>/<id>'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cleanup-undo-auto')));
      await tester.pumpAndSettle();
      expect(changes.last.undo, CleanupUndo.auto);
    });

    testWidgets('"Another request" lists the other requests of the collection, never the request itself, and stores the pick', (tester) async {
      final changes = await _pump(tester, _vm(createRequest(name: 'Create partner'), others: ['Partners/Delete partner', 'Health']), initial: const CleanupSettings(enabled: true));

      await tester.tap(find.byKey(const ValueKey('cleanup-undo-request')));
      await tester.pumpAndSettle();
      expect(changes.last.undo, CleanupUndo.request);
      await tester.tap(find.text('Pick a request'));
      await tester.pumpAndSettle();
      expect(find.text('Partners/Delete partner'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('Create partner'), findsNothing);
      await tester.tap(find.text('Partners/Delete partner').last);
      await tester.pumpAndSettle();

      expect(changes.last, const CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Partners/Delete partner'));
    });

    testWidgets('a chosen request that has been renamed away is marked not found, and a lone request says there is nothing to pick', (tester) async {
      await _pump(tester, _vm(createRequest(), others: ['Health']), initial: const CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Old name'));
      expect(find.textContaining('Old name (not found)'), findsOneWidget);

      await _pump(tester, _vm(createRequest()), initial: const CleanupSettings(enabled: true, undo: CleanupUndo.request));
      expect(find.text('This collection has no other request to send.'), findsOneWidget);
    });
  });

  group('inside the request Settings tab', () {
    late FakeRequestSettingsRepository requests;
    late FakeSettingsRepository global;

    Future<void> pumpTab(WidgetTester tester, {RequestSettings stored = RequestSettings.none, bool register = true, double width = 900}) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      requests = FakeRequestSettingsRepository()..stored[7] = stored;
      global = FakeSettingsRepository();
      locator.registerFactory<RequestSettingsViewModel>(() => RequestSettingsViewModel(requests, global));
      if (register) locator.registerFactory<CleanupSectionViewModel>(() => _vm(odooCreate(), others: ['Delete partner']));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: RequestSettingsTab(requestId: 7, isWeb: false))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the section sits below the overrides and is saved with them, under flow.cleanup', (tester) async {
      await pumpTab(tester, stored: const RequestSettings(timeoutSeconds: 12, flow: FlowSettings(alwaysRun: true)));

      expect(find.text('Request settings'), findsOneWidget);
      expect(find.text('Clean up what this request creates'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cleanup-use-suggestion')));
      await tester.pumpAndSettle();

      final saved = requests.stored[7]!;
      expect(saved.flow.cleanup, const CleanupSettings(enabled: true, undo: CleanupUndo.odooUnlink));
      expect(saved.timeoutSeconds, 12, reason: 'the overrides of the same row are kept');
      expect(saved.flow.alwaysRun, isTrue, reason: 'and so is the rest of the flow');
      expect(saved.toJson(), {
        'timeoutSeconds': 12,
        'flow': {
          'alwaysRun': true,
          'cleanup': {'enabled': true, 'undo': 'odooUnlink'},
        },
      });
    });

    testWidgets('an override edited afterwards does not undo the cleanup setting, and "use global" leaves it', (tester) async {
      await pumpTab(tester);
      await tester.tap(_switch());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '20');
      await tester.pump();
      await tester.tap(find.text('Use global settings for everything'));
      await tester.pumpAndSettle();

      expect(requests.stored[7]!.flow.cleanup.enabled, isTrue);
      expect(requests.stored[7]!.timeoutSeconds, isNull);
    });

    testWidgets('a tab built without the cleanup feature registered shows just the overrides, as it always did', (tester) async {
      await pumpTab(tester, register: false);

      expect(find.text('Request settings'), findsOneWidget);
      expect(find.text('Clean up what this request creates'), findsNothing);
    });

    testWidgets('does not overflow at phone width', (tester) async {
      await pumpTab(tester, width: 420, stored: const RequestSettings(flow: FlowSettings(cleanup: CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Delete partner'))));

      expect(find.text('Where is the created id?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
