import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/test_suggestions/domain/entities/baseline_settings.dart';
import 'package:postpilot/features/test_suggestions/domain/entities/drift_report.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_file.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_recorder.dart';
import 'package:postpilot/features/test_suggestions/domain/services/stability_probe.dart';
import 'package:postpilot/features/test_suggestions/presentation/view_models/baseline_view_model.dart';
import '../support/in_memory_import_export_fakes.dart';
import 'baseline_support.dart';
import 'response_fixtures.dart';

void main() {
  late InMemoryDb db;
  late InMemoryBaselines baselines;
  late List<(String, List<int>)> saved;
  String? savedTo;

  BaselineViewModel build(
    ApiResponseEntity response, {
    StabilityReport? Function()? stability,
    Future<BaselineFile> Function()? export,
  }) =>
      BaselineViewModel(
        requestId: 7,
        response: response,
        baselines: baselines,
        settings: db.requestSettingsRepository,
        export: export,
        stability: stability,
        saveFile: (name, bytes) async {
          saved.add((name, bytes));
          return savedTo;
        },
      );

  setUp(() {
    db = InMemoryDb();
    baselines = InMemoryBaselines();
    saved = [];
    savedTo = '/tmp/postpilot-baselines.json';
  });

  test('without a baseline there is nothing to compare, and enforcing is off', () async {
    final vm = build(response({'a': 1}));
    await vm.load();
    expect(vm.loaded, isTrue);
    expect(vm.hasBaseline, isFalse);
    expect(vm.report, isNull);
    expect(vm.enforce, isFalse);
  });

  group('record', () {
    test('keeps the response as the baseline, and the same response is then clean', () async {
      final vm = build(response(ordersBody()));
      await vm.load();
      await vm.record();
      expect(vm.hasBaseline, isTrue);
      expect(vm.report!.isClean, isTrue);
      expect(vm.notice, 'Baseline recorded: status 200 · 16 fields · 120 ms. It stays on this device.');
      expect(vm.noticeIsError, isFalse);
      expect(baselines.rows[7]!.snapshot.status, 200);
      expect(vm.busy, isFalse);
    });

    test('uses what the stability probe learned, and a later recording keeps it', () async {
      final a = ordersBody();
      final b = ordersBody(queueDepth: 99);
      final vm = build(response(a), stability: () => StabilityProbe.compare(a, b));
      await vm.load();
      await vm.record();
      expect(baselines.rows[7]!.snapshot.volatile, contains('queueDepth'));
      expect(baselines.rows[7]!.snapshot.values.containsKey('queueDepth'), isFalse);
      // Recorded again without a probe: the earlier knowledge stays.
      final again = build(response(a));
      await again.load();
      await again.record();
      expect(baselines.rows[7]!.snapshot.volatile, contains('queueDepth'));
    });

    test('is refused for a body cut off at the size limit, and says what to do', () async {
      final vm = build(response('{"a":1,"b":[', truncated: true));
      await vm.load();
      expect(vm.recordBlockedReason, contains('cut off at the size limit'));
      await vm.record();
      expect(vm.hasBaseline, isFalse);
      expect(vm.noticeIsError, isTrue);
      expect(baselines.rows, isEmpty);
    });

    test('a failure to save is told, and the view is not stuck busy', () async {
      baselines.failNextSave = true;
      final vm = build(response({'a': 1}));
      await vm.load();
      await vm.record();
      expect(vm.notice, 'That did not work: Bad state: disk full');
      expect(vm.noticeIsError, isTrue);
      expect(vm.busy, isFalse);
      expect(vm.hasBaseline, isFalse);
    });
  });

  group('drift', () {
    final original = {'id': 1, 'name': 'Ann', 'plan': 'free', 'tags': ['a']};
    // name removed (breaking), email added (non-breaking), plan changed (info)
    final changed = {'id': 1, 'plan': 'pro', 'email': 'a@b.co', 'tags': ['a']};

    Future<BaselineViewModel> drifted() async {
      await baselines.save(7, BaselineRecorder.record(response(original)));
      final vm = build(response(changed));
      await vm.load();
      return vm;
    }

    test('lists what changed, most serious first', () async {
      final vm = await drifted();
      expect(vm.report!.changes.map((c) => '${c.kind.name}:${c.path}'), ['fieldRemoved:name', 'fieldAdded:email', 'valueChanged:plan']);
      expect(vm.report!.verdict, DriftVerdict.breaking);
    });

    test('accepting one change takes only that one into the baseline', () async {
      final vm = await drifted();
      await vm.accept(vm.report!.changes.first);
      expect(vm.report!.changes.map((c) => c.kind.name), ['fieldAdded', 'valueChanged']);
      expect(baselines.rows[7]!.snapshot.fields.containsKey('name'), isFalse);
      expect(vm.notice, 'Change accepted: the baseline now has it.');
    });

    test('accepting all makes the response the baseline', () async {
      final vm = await drifted();
      await vm.acceptAll();
      expect(vm.report!.isClean, isTrue);
      expect(vm.notice, '3 changes accepted: the baseline matches this response.');
      expect(baselines.rows[7]!.snapshot.values['plan'], 'pro');
    });

    test('accepting with no baseline, or no changes, does nothing', () async {
      final vm = build(response(original));
      await vm.load();
      await vm.acceptAll();
      expect(baselines.rows, isEmpty);
      await baselines.save(7, BaselineRecorder.record(response(original)));
      final same = build(response(original));
      await same.load();
      await same.acceptAll();
      expect(same.notice, isNull);
    });

    test('a response cut off at the size limit is not compared', () async {
      await baselines.save(7, BaselineRecorder.record(response(original)));
      final vm = build(response('{"id":1,', truncated: true));
      await vm.load();
      expect(vm.hasBaseline, isTrue);
      expect(vm.report, isNull);
    });
  });

  group('reset and enforce', () {
    test('Enforce is stored in the request settings under "baseline", beside whatever else they hold', () async {
      db.requestSettings[7] = const RequestSettings(timeoutSeconds: 9, flow: FlowSettings(alwaysRun: true));
      final vm = build(response({'a': 1}));
      await vm.load();
      await vm.setEnforce(true);
      expect(vm.enforce, isTrue);
      final stored = db.requestSettings[7]!;
      expect(stored.baseline.enforce, isTrue);
      expect(stored.timeoutSeconds, 9);
      expect(stored.flow.alwaysRun, isTrue);
      await vm.setEnforce(false);
      expect(db.requestSettings[7]!.baseline.enforce, isFalse);
      expect(db.requestSettings[7]!.timeoutSeconds, 9);
    });

    test('turning it on with nothing else stores just that, and off removes the row', () async {
      final vm = build(response({'a': 1}));
      await vm.load();
      await vm.setEnforce(true);
      expect(db.requestSettings[7]!.encode(), '{"baseline":{"enforce":true}}');
      await vm.setEnforce(false);
      expect(db.requestSettings.containsKey(7), isFalse);
    });

    test('reset removes the baseline and turns Enforce off, leaving the rest of the settings alone', () async {
      await baselines.save(7, BaselineRecorder.record(response({'a': 1})));
      db.requestSettings[7] = const RequestSettings(timeoutSeconds: 9, baseline: BaselineSettings(enforce: true));
      final vm = build(response({'a': 1}));
      await vm.load();
      expect(vm.enforce, isTrue);
      await vm.reset();
      expect(vm.hasBaseline, isFalse);
      expect(vm.report, isNull);
      expect(vm.enforce, isFalse);
      expect(baselines.rows, isEmpty);
      expect(db.requestSettings[7]!.timeoutSeconds, 9);
      expect(db.requestSettings[7]!.baseline.enforce, isFalse);
      expect(vm.notice, 'Baseline removed.');
    });
  });

  group('export', () {
    BaselineFile twoEntries() => BaselineFile([
          BaselineFileEntry(collection: 'Shop', folder: '', name: 'List', method: 'GET', snapshot: BaselineRecorder.record(response({'a': 1}))),
          BaselineFileEntry(collection: 'Shop', folder: 'Orders', name: 'Get', method: 'GET', snapshot: BaselineRecorder.record(response({'b': 2}))),
        ]);

    test('saves the baselines of this device as the file the command line reads', () async {
      final vm = build(response({'a': 1}), export: () async => twoEntries());
      await vm.load();
      await vm.exportAll();
      expect(saved.single.$1, 'postpilot-baselines.json');
      final back = BaselineFile.parse(utf8.decode(Uint8List.fromList(saved.single.$2)));
      expect(back.entries.map((e) => e.name), ['List', 'Get']);
      expect(vm.notice, 'Exported 2 baselines to /tmp/postpilot-baselines.json. Pass the file to the command line with --baseline-file.');
      expect(vm.noticeIsError, isFalse);
    });

    test('with no baselines it says so and writes nothing; a cancelled save says nothing', () async {
      final empty = build(response({'a': 1}), export: () async => BaselineFile.empty);
      await empty.load();
      await empty.exportAll();
      expect(saved, isEmpty);
      expect(empty.notice, 'There are no baselines to export yet.');
      expect(empty.noticeIsError, isTrue);

      savedTo = null;
      final cancelled = build(response({'a': 1}), export: () async => twoEntries());
      await cancelled.load();
      await cancelled.exportAll();
      expect(saved, hasLength(1));
      expect(cancelled.notice, isNull);
    });
  });
}
