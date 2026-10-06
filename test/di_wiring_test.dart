// A missing or mis-wired registration only fails when a user opens the screen
// that asks the locator for it. These tests build the real container over an
// in-memory database and fail at once instead.
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/layout/layout_prefs.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/features/ai_assistant/data/ai_client.dart';
import 'package:postpilot/features/auth_renewal/domain/repositories/oauth2_token_store.dart';
import 'package:postpilot/features/auth_renewal/domain/services/oauth2_token_manager.dart';
import 'package:postpilot/features/auth_renewal/domain/usecases/relogin_usecase.dart';
import 'package:postpilot/features/auth_renewal/presentation/view_models/inherited_oauth2_status_view_model.dart';
import 'package:postpilot/features/auth_renewal/presentation/view_models/relogin_section_view_model.dart';
import 'package:postpilot/features/ai_assistant/data/ai_settings_store.dart';
import 'package:postpilot/features/dart_codegen/domain/usecases/build_api_layer_usecase.dart';
import 'package:postpilot/features/dart_codegen/presentation/view_models/api_layer_view_model.dart';
import 'package:postpilot/features/dart_codegen/presentation/view_models/api_tests_view_model.dart';
import 'package:postpilot/features/graphql/presentation/graphql_explorer_view_model.dart';
import 'package:postpilot/features/import_export/domain/usecases/refresh_openapi_usecase.dart';
import 'package:postpilot/features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_view_model.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import 'package:postpilot/features/odoo/presentation/view_models/odoo_studio_view_model.dart';
import 'package:postpilot/features/realtime/presentation/realtime_view_model.dart';
import 'package:postpilot/features/response_tools/domain/services/response_history.dart';
import 'package:postpilot/features/run_triage/domain/repositories/run_record_repository.dart';
import 'package:postpilot/features/run_triage/presentation/monitor_service.dart';
import 'package:postpilot/features/safety/data/safety_prefs.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:postpilot/features/test_suggestions/domain/repositories/request_baseline_repository.dart';
import 'package:postpilot/features/test_suggestions/domain/usecases/baseline_guard.dart';
import 'package:postpilot/features/test_suggestions/domain/usecases/export_baselines_usecase.dart';
import 'package:postpilot/features/test_suggestions/domain/usecases/generate_openapi_tests_usecase.dart';
import 'package:postpilot/features/templates/domain/usecases/add_starter_template_usecase.dart';
import 'package:postpilot/features/tour/presentation/tour_dialog.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_order_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/collections/presentation/view_models/collection_runner_view_model.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/console/presentation/view_models/request_console_log.dart';
import 'package:postpilot/features/cookies/domain/repositories/cookie_repository.dart';
import 'package:postpilot/features/cookies/presentation/view_models/cookies_view_model.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/domain/repositories/documentation_repository.dart';
import 'package:postpilot/features/documentation/domain/repositories/tag_repository.dart';
import 'package:postpilot/features/documentation/domain/usecases/build_api_docs_usecase.dart';
import 'package:postpilot/features/documentation/presentation/view_models/all_tags_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/collection_docs_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/entity_docs_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tag_filter_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tags_view_model.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/environments/presentation/view_models/environments_view_model.dart';
import 'package:postpilot/features/git_sync/data/repositories/entity_uid_registry.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_credentials_store.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_host_client.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_link_repository.dart';
import 'package:postpilot/features/git_sync/domain/repositories/local_collection_store.dart';
import 'package:postpilot/features/git_sync/domain/services/sync_engine.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_clone_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_commit_push_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_connect_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_contributors_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_create_branch_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_discard_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_disconnect_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_discover_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_history_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_list_branches_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_pull_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_save_token_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_status_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_switch_branch_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_update_link_settings_usecase.dart';
import 'package:postpilot/features/git_sync/presentation/view_models/git_clone_view_model.dart';
import 'package:postpilot/features/git_sync/presentation/view_models/git_sync_view_model.dart';
import 'package:postpilot/features/git_sync/presentation/view_models/linked_collections_view_model.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/history/presentation/view_models/history_view_model.dart';
import 'package:postpilot/features/settings/data/history_prefs.dart';
import 'package:postpilot/features/import_export/domain/repositories/git_state_store.dart';
import 'package:postpilot/features/import_export/domain/services/backup_service.dart';
import 'package:postpilot/features/import_export/domain/services/collection_loader.dart';
import 'package:postpilot/features/import_export/domain/services/imported_collection_writer.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_backup_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_openapi_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_postman_collection_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_any_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_har_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_insomnia_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_openapi_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_postman_collection_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_postman_environment_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/restore_backup_usecase.dart';
import 'package:postpilot/features/import_export/presentation/view_models/backup_view_model.dart';
import 'package:postpilot/features/import_export/presentation/view_models/export_collection_view_model.dart';
import 'package:postpilot/features/import_export/presentation/view_models/import_any_view_model.dart';
import 'package:postpilot/features/import_export/presentation/view_models/import_export_view_model.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/variable_scope.dart';
import 'package:postpilot/features/request_builder/domain/usecases/list_variables_usecase.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/services/oauth2_token_service.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/request_builder_view_model.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/request_oauth2_view_model.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/response_examples_view_model.dart';
import 'package:postpilot/features/defaults/domain/repositories/defaults_repository.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/defaults/presentation/view_models/defaults_view_model.dart';
import 'package:postpilot/features/defaults/presentation/view_models/inherited_defaults_view_model.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:postpilot/features/scripting/presentation/view_models/request_scripts_view_model.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/repositories/request_settings_repository.dart';
import 'package:postpilot/features/settings/domain/repositories/settings_repository.dart';
import 'package:postpilot/features/request_flow/domain/usecases/request_flow_service.dart';
import 'package:postpilot/features/request_flow/presentation/view_models/request_flow_view_model.dart';
import 'package:postpilot/features/settings/presentation/view_models/request_settings_view_model.dart';
import 'package:postpilot/features/settings/presentation/view_models/settings_view_model.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/domain/repositories/workplace_repository.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';

final class _Wiring {
  final String name;
  final Object Function() resolve;
  const _Wiring(this.name, this.resolve);
}

_Wiring _wire<T extends Object>([Object Function()? resolve]) => _Wiring('$T', resolve ?? () => locator<T>());

/// Every type setupDependencies registers. The coverage tests below fail when
/// this list and injector.dart drift apart.
final _wirings = <_Wiring>[
  _wire<AppDatabase>(),
  _wire<RequestConsoleLog>(),
  _wire<CookieJar>(),
  _wire<ApiClient>(),
  // collections
  _wire<CollectionRepository>(),
  _wire<CollectionOrderRepository>(),
  _wire<CollectionVariableRepository>(),
  _wire<CollectionAuthRepository>(),
  _wire<CollectionsViewModel>(),
  _wire<CollectionRunnerViewModel>(),
  // run history and the monitor
  _wire<RunRecordRepository>(),
  _wire<MonitorService>(),
  // request builder
  _wire<RequestRepository>(),
  _wire<RequestScriptsRepository>(),
  _wire<ResponseExampleRepository>(),
  _wire<OAuth2TokenService>(),
  _wire<BuildVariableResolverUseCase>(),
  _wire<SendRequestUseCase>(),
  _wire<GenerateCodeSnippetUseCase>(),
  _wire<CollectionRunnerService>(),
  _wire<RequestBuilderViewModel>(),
  _wire<ListVariablesUseCase>(),
  _wire<VariableScope>(),
  _wire<RequestOAuth2ViewModel>(),
  // self-renewing auth (OAuth 2.0 renewal before a send, re-login on 401/403)
  _wire<OAuth2TokenStore>(),
  _wire<OAuth2TokenManager>(),
  _wire<ReloginUseCase>(),
  _wire<ReloginSectionViewModel>(),
  _wire<InheritedOAuth2StatusViewModel>(),
  _wire<ResponseExamplesViewModel>(),
  // scripting
  _wire<RequestBaselineRepository>(),
  _wire<BaselineGuard>(),
  _wire<ExportBaselinesUseCase>(),
  _wire<GenerateOpenApiTestsUseCase>(),
  _wire<RunRequestScriptsUseCase>(),
  _wire<RequestScriptsViewModel>(),
  // defaults of collections and folders
  _wire<DefaultsRepository>(),
  _wire<ResolveRequestDefaultsUseCase>(),
  _wire<InheritedDefaultsViewModel>(),
  _wire<DefaultsViewModel>(),
  // environments, history, cookies, shell
  _wire<EnvironmentRepository>(),
  _wire<GlobalVariableRepository>(),
  _wire<EnvironmentsViewModel>(),
  _wire<HistoryPrefs>(),
  _wire<HistoryRepository>(),
  _wire<HistoryViewModel>(),
  _wire<CookieRepository>(),
  _wire<CookiesViewModel>(),
  _wire<ShellViewModel>(),
  _wire<LayoutPrefs>(),
  // settings
  _wire<SettingsRepository>(),
  _wire<RequestSettingsRepository>(),
  _wire<SettingsViewModel>(),
  _wire<RequestSettingsViewModel>(),
  // retry, poll until, run if, fetch all pages
  _wire<RequestFlowService>(),
  _wire<RequestFlowViewModel>(),
  // documentation
  _wire<DocumentationRepository>(),
  _wire<TagRepository>(),
  _wire<BuildApiDocsUseCase>(),
  _wire<TagFilterViewModel>(),
  _wire<EntityDocsViewModel>(() => locator<EntityDocsViewModel>(param1: EntityKind.request, param2: 1)),
  _wire<TagsViewModel>(() => locator<TagsViewModel>(param1: EntityKind.request, param2: 1)),
  _wire<AllTagsViewModel>(),
  _wire<CollectionDocsViewModel>(),
  // import / export
  _wire<ImportedCollectionWriter>(),
  _wire<CollectionLoader>(),
  _wire<BackupService>(),
  _wire<ImportPostmanCollectionUseCase>(),
  _wire<ImportPostmanEnvironmentUseCase>(),
  _wire<ExportPostmanCollectionUseCase>(),
  _wire<ImportCurlUseCase>(),
  _wire<ImportOpenApiUseCase>(),
  _wire<ImportInsomniaUseCase>(),
  _wire<ImportHarUseCase>(),
  _wire<ImportCurlScriptUseCase>(),
  _wire<ExportOpenApiUseCase>(),
  _wire<ExportCurlScriptUseCase>(),
  _wire<ExportBackupUseCase>(),
  _wire<RestoreBackupUseCase>(),
  _wire<ImportAnyUseCase>(),
  _wire<ImportExportViewModel>(),
  _wire<ImportAnyViewModel>(),
  _wire<ExportCollectionViewModel>(),
  _wire<BackupViewModel>(),
  // git sync
  _wire<GitCredentialsStore>(),
  _wire<GitHostClient>(),
  _wire<GitLinkRepository>(),
  _wire<EntityUidRegistry>(),
  _wire<LocalCollectionStore>(),
  _wire<GitStateStore>(),
  _wire<SyncEngine>(),
  _wire<GitSaveTokenUseCase>(),
  _wire<GitDiscoverUseCase>(),
  _wire<GitConnectUseCase>(),
  _wire<GitCloneUseCase>(),
  _wire<GitStatusUseCase>(),
  _wire<GitCommitPushUseCase>(),
  _wire<GitPullUseCase>(),
  _wire<GitDiscardUseCase>(),
  _wire<GitListBranchesUseCase>(),
  _wire<GitCreateBranchUseCase>(),
  _wire<GitSwitchBranchUseCase>(),
  _wire<GitContributorsUseCase>(),
  _wire<GitHistoryUseCase>(),
  _wire<GitUpdateLinkSettingsUseCase>(),
  _wire<GitDisconnectUseCase>(),
  _wire<LinkedCollectionsViewModel>(),
  _wire<GitSyncViewModel>(),
  _wire<GitCloneViewModel>(),
  // workplace
  _wire<WorkplaceRepository>(),
  _wire<WorkplaceViewModel>(),
  // developer tools
  _wire<BuildApiLayerUseCase>(),
  _wire<ApiLayerViewModel>(),
  _wire<ApiTestsViewModel>(),
  _wire<ResponseHistory>(),
  _wire<SafetyPrefs>(),
  _wire<ProductionGuard>(),
  _wire<TourPrefs>(),
  _wire<AiSettingsStore>(),
  _wire<AiClient>(),
  _wire<AddStarterTemplateUseCase>(),
  _wire<RefreshOpenApiUseCase>(),
  _wire<BuildMockRoutesUseCase>(),
  _wire<MockServerViewModel>(),
  _wire<GraphqlExplorerViewModel>(),
  _wire<RealtimeViewModel>(),
  _wire<OdooClient>(),
  _wire<CreateOdooWorkspaceUseCase>(),
  _wire<OdooStudioViewModel>(),
];

final _registration = RegExp(r'\bregister(?:Lazy)?(?:Singleton|Factory|FactoryParam)<(\w+)');
final _locatorUse = RegExp(r'\blocator<(\w+)>');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  final resolved = Set<Object>.identity();

  setUpAll(() async {
    await locator.reset();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    setupDependencies(database: database);
  });

  tearDownAll(() async {
    for (final instance in resolved) {
      if (instance is ChangeNotifier) instance.dispose();
    }
    await locator.reset();
    await database.close();
  });

  group('every registration builds', () {
    for (final wiring in _wirings) {
      test(wiring.name, () {
        final instance = wiring.resolve();
        resolved.add(instance);
        expect(instance, isNotNull);
      });
    }
  });

  group('the registrations and their users agree', () {
    test('this test lists every type the injector registers', () {
      final registered = {
        for (final match in _registration.allMatches(File('lib/core/di/injector.dart').readAsStringSync()))
          match.group(1)!,
      };
      final listed = {for (final wiring in _wirings) wiring.name};

      expect(registered.difference(listed), isEmpty, reason: 'registered in injector.dart but missing from _wirings');
      expect(listed.difference(registered), isEmpty, reason: 'listed in _wirings but not registered any more');
    });

    test('every type the app asks the locator for is registered', () {
      final listed = {for (final wiring in _wirings) wiring.name};
      final asked = <String>{};
      final missing = <String, Set<String>>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final match in _locatorUse.allMatches(entity.readAsStringSync())) {
          final type = match.group(1)!;
          asked.add(type);
          if (!listed.contains(type)) missing.putIfAbsent(type, () => {}).add(entity.path);
        }
      }

      expect(asked, isNotEmpty, reason: 'the scan found no locator<T>() calls, so it checks nothing');
      expect(missing, isEmpty, reason: 'locator<T>() is called for a T that setupDependencies never registers');
    });
  });

  group('the container is wired together', () {
    test('the database given to setupDependencies is the one everything uses', () async {
      expect(locator<AppDatabase>(), same(database));

      final id = await locator<CollectionRepository>().createCollection('Wired');

      final rows = await database.select(database.collections).get();
      expect(rows.map((row) => row.id), contains(id));
    });

    test('settings load from the database, as main() does before the first frame', () async {
      final settings = locator<SettingsRepository>();

      await settings.load();

      expect(settings.current, const AppSettings());
    });

    test('the sidebar follows the tag filter through the registered instances', () async {
      final collections = locator<CollectionRepository>();
      final requests = locator<RequestRepository>();
      final collectionId = await collections.createCollection('Shop');
      final tagged = await requests.createRequest(collectionId: collectionId, name: 'List users');
      final untagged = await requests.createRequest(collectionId: collectionId, name: 'Health');
      await locator<TagRepository>().setTags(EntityKind.request, tagged, ['v2']);
      final sidebar = locator<CollectionsViewModel>();
      final filter = locator<TagFilterViewModel>();
      await pumpEventQueue(times: 60);

      filter.toggleTag('v2');
      await pumpEventQueue(times: 60);

      final shop = sidebar.collections.firstWhere((c) => c.id == collectionId);
      bool visible(int id) =>
          sidebar.isRequestVisible(sidebar.requestsByCollection[collectionId]!.firstWhere((r) => r.id == id));
      expect(sidebar.isFiltering, isTrue);
      expect(sidebar.isCollectionExpanded(shop), isTrue);
      expect(visible(tagged), isTrue);
      expect(visible(untagged), isFalse);

      filter.clear();
      await pumpEventQueue(times: 60);

      expect(sidebar.isFiltering, isFalse);
      expect(visible(untagged), isTrue);
    });
  });
}
