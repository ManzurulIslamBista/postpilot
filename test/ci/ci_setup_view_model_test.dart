// The state behind the "Set up CI" dialog: what it preselects, how the choices change the generated files, and what
// saving into the repository does in each case.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/ci/data/ci_workflow_writer.dart';
import 'package:postpilot/features/ci/domain/entities/ci_options.dart';
import 'package:postpilot/features/ci/presentation/ci_setup_view_model.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import '../support/in_memory_import_export_fakes.dart';

final class _Writer implements CiWorkflowWriter {
  _Writer({this.root = '/repo', this.canWriteFiles = true, this.result = const WorkflowSaved('.github/workflows/postpilot.yml')});

  final String? root;
  final bool canWriteFiles;
  WorkflowSaveResult result;
  final saved = <({String yaml, bool overwrite})>[];

  @override
  bool get canWrite => canWriteFiles;

  @override
  Future<String?> findRepositoryRoot(String folderPath) async => root;

  @override
  String workspacePathIn(String repositoryRoot, String workspaceFolder) => 'services/api/workspace.json';

  @override
  Future<bool> workspaceFileExists(String workspaceFolder) async => true;

  @override
  Future<WorkflowSaveResult> save(String repositoryRoot, String yaml, {bool overwrite = false}) async {
    saved.add((yaml: yaml, overwrite: overwrite));
    return result;
  }
}

void main() {
  late InMemoryDb db;

  setUp(() async {
    db = InMemoryDb();
    await db.collectionRepository.createCollection('Shop');
    await db.collectionRepository.createCollection('Billing');
    final dev = await db.environmentRepository.create('Dev');
    final production = await db.environmentRepository.create('Production');
    await db.environmentRepository.setActive(dev);
    Future<void> variable(int env, String key, {bool secret = false, bool enabled = true}) => db.environmentRepository.upsertVariable(
          EnvironmentVariableEntity(id: 0, environmentId: env, key: key, value: 'v', isSecret: secret, enabled: enabled),
        );
    await variable(dev, 'devKey', secret: true);
    await variable(dev, 'bad name', secret: true);
    await variable(dev, 'plain');
    await variable(production, 'prodKey', secret: true);
    await db.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'sharedToken', value: '', isSecret: true, enabled: true));
    await db.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'disabledToken', value: '', isSecret: true, enabled: false));
  });

  CiSetupViewModel make(_Writer writer, {String? folder = '/repo/services/api', List<String> words = const []}) => CiSetupViewModel(
        environments: db.environmentRepository,
        globals: db.globalVariableRepository,
        collections: db.collectionRepository,
        writer: writer,
        project: CiProject(folderPath: folder, name: 'API'),
        productionWords: words,
      );

  group('loading', () {
    test('preselects the active environment, the path in the repository and the collection it was opened from', () async {
      final vm = make(_Writer());
      await vm.load(collectionName: 'Billing');
      expect(vm.isLoading, isFalse);
      expect(vm.options.environment, 'Dev');
      expect(vm.options.collection, 'Billing');
      expect(vm.options.workspacePath, 'services/api/workspace.json');
      expect(vm.repositoryRoot, '/repo');
      expect(vm.workspaceFileFound, isTrue);
      expect(vm.environments.map((e) => e.name), ['Dev', 'Production']);
      expect(vm.collectionNames, ['Shop', 'Billing']);
    });

    test('a collection that does not exist is not preselected', () async {
      final vm = make(_Writer());
      await vm.load(collectionName: 'Nope');
      expect(vm.options.collection, isNull);
    });

    test('a preferred environment beats the active one', () async {
      final vm = make(_Writer());
      await vm.load(preferredEnvironment: 'Production');
      expect(vm.options.environment, 'Production');
    });

    test('the secrets are the enabled secret variables of the environment and the enabled secret globals, by name', () async {
      final vm = make(_Writer());
      await vm.load();
      expect([for (final s in vm.options.secrets) (s.variable, s.secretName)], [('devKey', 'DEV_KEY'), ('sharedToken', 'SHARED_TOKEN')]);
      expect(vm.skippedSecrets.single, contains('"bad name"'));
    });

    test('no folder on disk (a browser) means no repository and a reason why', () async {
      final vm = make(_Writer(), folder: null);
      await vm.load();
      expect(vm.repositoryRoot, isNull);
      expect(vm.saveBlocker, contains('no folder on disk'));
      expect(vm.canSaveToRepository, isFalse);
    });

    test('a platform that cannot write says so first', () async {
      final vm = make(_Writer(canWriteFiles: false));
      await vm.load();
      expect(vm.saveBlocker, contains('cannot write files'));
    });

    test('a folder outside a Git repository can be copied from, not saved', () async {
      final vm = make(_Writer(root: null));
      await vm.load();
      expect(vm.saveBlocker, contains('not inside a Git repository'));
      expect(vm.text, contains('name: PostPilot API tests'));
    });
  });

  group('the choices', () {
    test('changing the environment changes the secrets and the command', () async {
      final vm = make(_Writer());
      await vm.load();
      vm.setEnvironment('Production');
      expect([for (final s in vm.options.secrets) s.secretName], ['PROD_KEY', 'SHARED_TOKEN']);
      expect(vm.text, contains('--env Production'));
      vm.setEnvironment(null);
      expect(vm.text, isNot(contains('--env')));
      expect([for (final s in vm.options.secrets) s.secretName], ['SHARED_TOKEN']);
    });

    test('the target picks which file is shown', () async {
      final vm = make(_Writer());
      await vm.load();
      expect(vm.text, startsWith('# Generated by PostPilot'));
      vm.setTarget(CiTarget.gitlab);
      expect(vm.text, contains('postpilot-api-tests:'));
      vm.setTarget(CiTarget.shell);
      expect(vm.text, startsWith('#!/usr/bin/env bash'));
    });

    test('a problem in any choice hides the files and blocks saving, with what to change', () async {
      final vm = make(_Writer());
      await vm.load();
      vm.setSchedule(CiSchedulePreset.custom);
      vm.setCustomCron('* * * * *');
      expect(vm.text, isNull);
      expect(vm.problems['cron'], contains('every 1 minute'));
      expect(vm.canSaveToRepository, isFalse);
      vm.setCustomCron('*/30 * * * *');
      expect(vm.problems, isEmpty);
      expect(vm.text, contains("cron: '*/30 * * * *'"));
      expect(vm.canSaveToRepository, isTrue);
    });

    test('production looking environments are noticed, with your own words too', () async {
      final vm = make(_Writer(), words: ['dev']);
      await vm.load();
      expect(vm.environmentLooksProduction, isTrue, reason: 'Dev is production by your own word');
      final plain = make(_Writer());
      await plain.load();
      expect(plain.environmentLooksProduction, isFalse);
      plain.setEnvironment('Production');
      expect(plain.environmentLooksProduction, isTrue);
    });

    test('allowing production is off until it is chosen', () async {
      final vm = make(_Writer());
      await vm.load();
      expect(vm.options.allowProduction, isFalse);
      expect(vm.text, isNot(contains('--allow-production')));
      vm.setAllowProduction(true);
      expect(vm.text, contains('--allow-production'));
    });
  });

  group('saving', () {
    test('writes the GitHub workflow and says what to do next', () async {
      final writer = _Writer();
      final vm = make(writer);
      await vm.load();
      final result = await vm.saveToRepository();
      expect(result, isA<WorkflowSaved>());
      expect(writer.saved.single.overwrite, isFalse);
      expect(writer.saved.single.yaml, contains('name: PostPilot API tests'));
      expect(vm.saveMessage, contains('Saved .github/workflows/postpilot.yml. Commit and push it'));
      expect(vm.saveFailed, isFalse);
      expect(vm.isSaving, isFalse);
    });

    test('a different file already there is not touched until the caller asks again with overwrite', () async {
      final writer = _Writer(result: const WorkflowNeedsConfirmation('.github/workflows/postpilot.yml'));
      final vm = make(writer);
      await vm.load();
      expect(await vm.saveToRepository(), isA<WorkflowNeedsConfirmation>());
      expect(vm.saveMessage, isNull, reason: 'nothing was saved, so there is nothing to report');
      expect(vm.isSaving, isFalse);
      writer.result = const WorkflowSaved('.github/workflows/postpilot.yml', replaced: true);
      await vm.saveToRepository(overwrite: true);
      expect(writer.saved.map((s) => s.overwrite), [false, true]);
      expect(vm.saveMessage, startsWith('Replaced .github/workflows/postpilot.yml'));
    });

    test('an identical file is said to be up to date', () async {
      final vm = make(_Writer(result: const WorkflowUnchanged('.github/workflows/postpilot.yml')));
      await vm.load();
      await vm.saveToRepository();
      expect(vm.saveMessage, contains('already holds exactly this workflow'));
    });

    test('a write that failed says why, in red', () async {
      final vm = make(_Writer(result: const WorkflowSaveFailed('Could not write: access denied. Check the folder is writable.')));
      await vm.load();
      await vm.saveToRepository();
      expect(vm.saveFailed, isTrue);
      expect(vm.saveMessage, contains('access denied'));
    });

    test('nothing is written outside a repository or with a problem in the choices', () async {
      final writer = _Writer(root: null);
      final vm = make(writer);
      await vm.load();
      final result = await vm.saveToRepository();
      expect(result, isA<WorkflowSaveFailed>());
      expect(writer.saved, isEmpty);

      final other = _Writer();
      final bad = make(other);
      await bad.load();
      bad.setPostpilotRef('main; rm -rf /');
      expect(await bad.saveToRepository(), isA<WorkflowSaveFailed>());
      expect(other.saved, isEmpty);
    });

    test('changing a choice clears what the last save said', () async {
      final vm = make(_Writer());
      await vm.load();
      await vm.saveToRepository();
      expect(vm.saveMessage, isNotNull);
      vm.setBail(true);
      expect(vm.saveMessage, isNull);
    });
  });
}
