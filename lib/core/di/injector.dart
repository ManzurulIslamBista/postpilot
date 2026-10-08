import '../layout/layout_prefs.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/dio_api_client.dart';
import '../network/logging_api_client.dart';
import '../network/strict_cookie_jar.dart';
import '../../features/auth_renewal/data/repository_oauth2_token_store.dart';
import '../../features/auth_renewal/domain/repositories/oauth2_token_store.dart';
import '../../features/auth_renewal/domain/services/oauth2_token_manager.dart';
import '../../features/auth_renewal/domain/usecases/relogin_usecase.dart';
import '../../features/auth_renewal/domain/usecases/renew_request_auth_usecase.dart';
import '../../features/auth_renewal/presentation/view_models/inherited_oauth2_status_view_model.dart';
import '../../features/auth_renewal/presentation/view_models/relogin_section_view_model.dart';
import '../../features/collections/data/repositories/collection_auth_repository_impl.dart';
import '../../features/collections/data/repositories/collection_order_repository_impl.dart';
import '../../features/collections/data/repositories/collection_repository_impl.dart';
import '../../features/collections/data/repositories/collection_variable_repository_impl.dart';
import '../../features/collections/domain/repositories/collection_auth_repository.dart';
import '../../features/collections/domain/repositories/collection_order_repository.dart';
import '../../features/collections/domain/repositories/collection_repository.dart';
import '../../features/collections/domain/repositories/collection_variable_repository.dart';
import '../../features/collections/presentation/view_models/collection_runner_view_model.dart';
import '../../features/collections/presentation/view_models/collections_view_model.dart';
import '../../features/defaults/data/defaults_repository_impl.dart';
import '../../features/defaults/domain/repositories/defaults_repository.dart';
import '../../features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import '../../features/defaults/presentation/view_models/defaults_view_model.dart';
import '../../features/defaults/presentation/view_models/inherited_defaults_view_model.dart';
import '../../features/request_builder/domain/services/request_spec_builder.dart';
import '../../features/scripting/domain/evaluator/assertion_evaluator.dart';
import '../../features/console/presentation/view_models/request_console_log.dart';
import '../../features/cookies/data/repositories/cookie_repository_impl.dart';
import '../../features/cookies/domain/repositories/cookie_repository.dart';
import '../../features/cookies/presentation/view_models/cookies_view_model.dart';
import '../../features/documentation/data/repositories/documentation_repository_impl.dart';
import '../../features/documentation/data/repositories/tag_repository_impl.dart';
import '../../features/documentation/domain/entities/entity_kind.dart';
import '../../features/documentation/domain/repositories/documentation_repository.dart';
import '../../features/documentation/domain/repositories/tag_repository.dart';
import '../../features/documentation/domain/usecases/build_api_docs_usecase.dart';
import '../../features/documentation/presentation/view_models/all_tags_view_model.dart';
import '../../features/documentation/presentation/view_models/collection_docs_view_model.dart';
import '../../features/documentation/presentation/view_models/entity_docs_view_model.dart';
import '../../features/documentation/presentation/view_models/tag_filter_view_model.dart';
import '../../features/documentation/presentation/view_models/tags_view_model.dart';
import '../../features/ai_assistant/data/ai_client.dart';
import '../../features/ai_assistant/data/ai_settings_store.dart';
import '../../features/dart_codegen/data/settings_model_snapshot_store.dart';
import '../../features/dart_codegen/domain/repositories/model_snapshot_store.dart';
import '../../features/dart_codegen/domain/usecases/build_api_layer_usecase.dart';
import '../../features/graphql/presentation/graphql_explorer_view_model.dart';
import '../../features/import_export/domain/usecases/refresh_openapi_usecase.dart';
import '../../features/device_helper/data/device_host.dart';
import '../../features/device_helper/domain/services/device_detector.dart';
import '../../features/cors_proxy/data/cors_proxy_settings_store.dart';
import '../../features/cors_proxy/presentation/cors_proxy_server_view_model.dart';
import '../../features/cors_proxy/presentation/cors_proxy_settings_view_model.dart';
import '../../features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import '../../features/mock_server/presentation/mock_server_view_model.dart';
import '../../features/traffic_recorder/domain/usecases/create_collection_from_recording_usecase.dart';
import '../../features/traffic_recorder/presentation/traffic_recorder_view_model.dart';
import '../../features/odoo/data/odoo_client.dart';
import '../../features/odoo/data/odoo_doctor.dart';
import '../../features/odoo/data/odoo_smart_resolver.dart';
import '../../features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import '../../features/settings/domain/services/tool_request_options.dart';
import '../../features/odoo/presentation/view_models/odoo_studio_view_model.dart';
import '../../features/realtime/data/realtime_session.dart';
import '../../features/realtime/presentation/realtime_view_model.dart';
import '../../features/response_tools/domain/services/response_history.dart';
import '../../features/templates/domain/usecases/add_starter_template_usecase.dart';
import '../../features/tour/presentation/tour_dialog.dart';
import '../../features/safety/data/safety_prefs.dart';
import '../../features/safety/domain/services/production_guard.dart';
import '../../features/dart_codegen/presentation/view_models/api_layer_view_model.dart';
import '../../features/dart_codegen/presentation/view_models/api_tests_view_model.dart';
import '../../features/environments/data/repositories/environment_repository_impl.dart';
import '../../features/environments/data/repositories/global_variable_repository_impl.dart';
import '../../features/environments/domain/repositories/environment_repository.dart';
import '../../features/environments/domain/repositories/global_variable_repository.dart';
import '../../features/environments/presentation/view_models/environments_view_model.dart';
import '../../features/git_sync/data/github/github_host_client.dart';
import '../../features/git_sync/data/repositories/drift_git_state_store.dart';
import '../../features/git_sync/data/repositories/entity_uid_registry.dart';
import '../../features/git_sync/data/repositories/git_link_repository_impl.dart';
import '../../features/git_sync/data/repositories/local_collection_store_impl.dart';
import '../../features/git_sync/data/secure_git_credentials_store.dart';
import '../../features/git_sync/domain/repositories/git_credentials_store.dart';
import '../../features/git_sync/domain/repositories/git_host_client.dart';
import '../../features/git_sync/domain/repositories/git_link_repository.dart';
import '../../features/git_sync/domain/repositories/local_collection_store.dart';
import '../../features/git_sync/domain/services/sync_engine.dart';
import '../../features/git_sync/domain/usecases/git_clone_usecase.dart';
import '../../features/git_sync/domain/usecases/git_commit_push_usecase.dart';
import '../../features/git_sync/domain/usecases/git_connect_usecase.dart';
import '../../features/git_sync/domain/usecases/git_contributors_usecase.dart';
import '../../features/git_sync/domain/usecases/git_create_branch_usecase.dart';
import '../../features/git_sync/domain/usecases/git_discard_usecase.dart';
import '../../features/git_sync/domain/usecases/git_disconnect_usecase.dart';
import '../../features/git_sync/domain/usecases/git_discover_usecase.dart';
import '../../features/git_sync/domain/usecases/git_history_usecase.dart';
import '../../features/git_sync/domain/usecases/git_list_branches_usecase.dart';
import '../../features/git_sync/domain/usecases/git_pull_usecase.dart';
import '../../features/git_sync/domain/usecases/git_save_token_usecase.dart';
import '../../features/git_sync/domain/usecases/git_status_usecase.dart';
import '../../features/git_sync/domain/usecases/git_switch_branch_usecase.dart';
import '../../features/git_sync/domain/usecases/git_update_link_settings_usecase.dart';
import '../../features/git_sync/presentation/view_models/git_clone_view_model.dart';
import '../../features/git_sync/presentation/view_models/git_sync_view_model.dart';
import '../../features/git_sync/presentation/view_models/linked_collections_view_model.dart';
import '../../features/history/data/repositories/history_repository_impl.dart';
import '../../features/history/data/repository_history_context_source.dart';
import '../../features/history/domain/repositories/history_repository.dart';
import '../../features/settings/data/history_prefs.dart';
import '../../features/history/presentation/view_models/history_view_model.dart';
import '../../features/import_export/domain/repositories/git_state_store.dart';
import '../../features/import_export/domain/services/backup_service.dart';
import '../../features/import_export/domain/services/collection_loader.dart';
import '../../features/import_export/domain/services/imported_collection_writer.dart';
import '../../features/import_export/domain/usecases/export_backup_usecase.dart';
import '../../features/import_export/domain/usecases/export_curl_script_usecase.dart';
import '../../features/import_export/domain/usecases/export_openapi_usecase.dart';
import '../../features/import_export/domain/usecases/export_postman_collection_usecase.dart';
import '../../features/import_export/domain/usecases/import_any_usecase.dart';
import '../../features/import_export/domain/usecases/import_curl_script_usecase.dart';
import '../../features/import_export/domain/usecases/import_curl_usecase.dart';
import '../../features/import_export/domain/usecases/import_har_usecase.dart';
import '../../features/import_export/domain/usecases/import_insomnia_usecase.dart';
import '../../features/import_export/domain/usecases/import_openapi_usecase.dart';
import '../../features/import_export/domain/usecases/import_postman_collection_usecase.dart';
import '../../features/import_export/domain/usecases/import_postman_environment_usecase.dart';
import '../../features/import_export/domain/usecases/restore_backup_usecase.dart';
import '../../features/import_export/presentation/view_models/backup_view_model.dart';
import '../../features/import_export/presentation/view_models/export_collection_view_model.dart';
import '../../features/import_export/presentation/view_models/import_any_view_model.dart';
import '../../features/import_export/presentation/view_models/import_export_view_model.dart';
import '../../features/request_builder/presentation/view_models/variable_scope.dart';
import '../../features/request_builder/domain/usecases/list_variables_usecase.dart';
import '../../features/request_builder/data/repositories/request_repository_impl.dart';
import '../../features/request_builder/data/repositories/request_scripts_repository_impl.dart';
import '../../features/request_builder/data/repositories/response_example_repository_impl.dart';
import '../../features/request_builder/domain/repositories/request_repository.dart';
import '../../features/request_builder/domain/repositories/request_scripts_repository.dart';
import '../../features/request_builder/domain/repositories/response_example_repository.dart';
import '../../features/request_builder/domain/services/collection_runner_service.dart';
import '../../features/request_builder/domain/services/oauth2_token_service.dart';
import '../../features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import '../../features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import '../../features/request_builder/domain/usecases/send_request_usecase.dart';
import '../../features/request_flow/data/app_flow_environment.dart';
import '../../features/request_flow/domain/usecases/request_flow_service.dart';
import '../../features/request_flow/presentation/view_models/request_flow_view_model.dart';
import '../../features/request_builder/presentation/view_models/request_builder_view_model.dart';
import '../../features/request_builder/presentation/view_models/request_oauth2_view_model.dart';
import '../../features/request_builder/presentation/view_models/response_examples_view_model.dart';
import '../../features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../../features/scripting/presentation/view_models/request_scripts_view_model.dart';
import '../../features/test_suggestions/data/request_baseline_repository_impl.dart';
import '../../features/test_suggestions/domain/repositories/request_baseline_repository.dart';
import '../../features/test_suggestions/domain/usecases/baseline_guard.dart';
import '../../features/test_suggestions/domain/usecases/export_baselines_usecase.dart';
import '../../features/test_suggestions/domain/usecases/generate_openapi_tests_usecase.dart';
import '../../features/settings/data/repositories/request_settings_repository_impl.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/data/secure_proxy_password_store.dart';
import '../../features/settings/domain/repositories/request_settings_repository.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';
import '../../features/settings/presentation/view_models/request_settings_view_model.dart';
import '../../features/settings/presentation/view_models/settings_view_model.dart';
import '../../features/shell/presentation/shell_view_model.dart';
import '../../features/workspace_refactor/domain/entities/refactor_receipt.dart';
import '../../features/workspace_refactor/domain/services/refactor_applier.dart';
import '../../features/workspace_refactor/domain/services/refactor_writer.dart';
import '../../features/workspace_refactor/domain/services/workspace_reader.dart';
import '../../features/workspace_refactor/presentation/view_models/workspace_refactor_view_model.dart';
import '../../features/workplace/data/repositories/workplace_repository_impl.dart';
import '../../features/workplace/domain/repositories/workplace_repository.dart';
import '../../features/workplace/presentation/view_models/workplace_view_model.dart';
import '../../features/run_triage/data/run_record_repository_impl.dart';
import '../../features/run_triage/data/settings_monitor_config_store.dart';
import '../../features/run_triage/domain/repositories/run_record_repository.dart';
import '../../features/run_triage/domain/services/monitor_runner.dart';
import '../../features/run_triage/presentation/monitor_service.dart';
import '../../features/matrix_run/data/cookie_session_isolation.dart';
import '../../features/matrix_run/data/settings_matrix_identity_store.dart';
import '../../features/matrix_run/domain/repositories/matrix_identity_store.dart';
import '../../features/matrix_run/domain/services/matrix_run_service.dart';
import '../../features/matrix_run/presentation/matrix_run_view_model.dart';
import '../../features/safety/domain/services/production_detector.dart';
import '../../features/cleanup_ledger/data/app_cleanup_sender.dart';
import '../../features/cleanup_ledger/presentation/view_models/cleanup_ledger.dart';
import '../../features/cleanup_ledger/presentation/view_models/cleanup_section_view_model.dart';

final locator = GetIt.instance;

/// Registers every dependency, grouped by feature. View models come in three
/// lifetimes: app-session ones are lazy singletons that app.dart provides
/// above MaterialApp (so dialogs, which attach to the root navigator, a sibling
/// of the page tree rather than a descendant, can still reach them); the
/// others are factories, giving each request tab, editor or dialog a fresh
/// instance.
///
/// [database] replaces the on-disk database, so a test can pass an in-memory one.
void setupDependencies({AppDatabase? database}) {
  _registerCore(database ?? AppDatabase());
  _registerCollections();
  _registerRunTriage();
  _registerRequestBuilder();
  _registerScripting();
  _registerDefaults();
  _registerEnvironments();
  _registerHistory();
  _registerCookies();
  _registerShell();
  _registerSettings();
  _registerDocumentation();
  _registerImportExport();
  _registerGitSync();
  _registerWorkplace();
  _registerDevTools();
  _registerWorkspaceRefactor();
  _registerMatrixRun();
  _registerCleanupLedger();
}

/// Matrix run: one collection against several environments or identities, compared on a grid. The identities are kept
/// per workplace in the settings table, on this device only.
void _registerMatrixRun() {
  locator.registerLazySingleton<MatrixIdentityStore>(
    () => SettingsMatrixIdentityStore(
      locator<AppDatabase>().settingsDao,
      () async => (await locator<WorkplaceRepository>().getActiveWorkplace())?.id,
    ),
  );
  locator.registerLazySingleton<MatrixRunner>(
    () => MatrixRunService(
      locator<CollectionRunnerService>(),
      locator<EnvironmentRepository>(),
      guard: locator<ProductionGuard>(),
      sessions: CookieSessionIsolation(locator<CookieJar>()),
    ),
  );
  locator.registerFactory<MatrixRunViewModel>(
    () => MatrixRunViewModel(
      runner: locator<MatrixRunner>(),
      identities: locator<MatrixIdentityStore>(),
      environments: locator<EnvironmentRepository>(),
      collections: locator<CollectionRepository>(),
      picker: locator<CollectionRunnerViewModel>(),
      isProduction: (name) => ProductionDetector.isProduction(name, extraWords: locator<SafetyPrefs>().extraWords),
    ),
  );
}

/// Developer tools: generators and helpers that sit beside the request builder.
void _registerDevTools() {
  locator.registerLazySingleton<BuildApiLayerUseCase>(
    () => BuildApiLayerUseCase(locator<CollectionLoader>(), locator<ResponseExampleRepository>()),
  );
  locator.registerLazySingleton<ModelSnapshotStore>(() => SettingsModelSnapshotStore(locator<AppDatabase>().settingsDao));
  locator.registerFactory<ApiLayerViewModel>(
    () => ApiLayerViewModel(locator<BuildApiLayerUseCase>(), locator<ModelSnapshotStore>()),
  );
  locator.registerFactory<ApiTestsViewModel>(() => ApiTestsViewModel(locator<BuildApiLayerUseCase>()));
  locator.registerLazySingleton<ResponseHistory>(ResponseHistory.new);
  locator.registerLazySingleton<SafetyPrefs>(SafetyPrefs.new);
  locator.registerLazySingleton<ProductionGuard>(
    () => ProductionGuard(
      locator<EnvironmentRepository>(),
      locator<SafetyPrefs>(),
      // Resolves {{baseUrl}} the way a send does, so the production-host list sees the real host.
      (r) async => (await locator<BuildVariableResolverUseCase>()(r.collectionId, folderId: r.folderId)).resolve(r.url),
    ),
  );
  locator.registerLazySingleton<TourPrefs>(TourPrefs.new);
  locator.registerLazySingleton<AiSettingsStore>(SecureAiSettingsStore.new);
  locator.registerLazySingleton<AiClient>(
    () => AiClient(locator<ApiClient>(), locator<AiSettingsStore>(), appSettings: locator<SettingsRepository>()),
  );
  locator.registerLazySingleton<AddStarterTemplateUseCase>(
    () => AddStarterTemplateUseCase(locator<ImportedCollectionWriter>(), locator<EnvironmentRepository>()),
  );
  locator.registerLazySingleton<RefreshOpenApiUseCase>(
    () => RefreshOpenApiUseCase(locator<CollectionRepository>(), locator<RequestRepository>()),
  );
  locator.registerLazySingleton<BuildMockRoutesUseCase>(
    () => BuildMockRoutesUseCase(locator<CollectionLoader>(), locator<ResponseExampleRepository>()),
  );
  // One for the whole session: the server keeps answering after its dialog closes.
  locator.registerLazySingleton<MockServerViewModel>(() => MockServerViewModel(locator<BuildMockRoutesUseCase>()));
  locator.registerLazySingleton<CreateCollectionFromRecordingUseCase>(
    () => CreateCollectionFromRecordingUseCase(
      locator<ImportedCollectionWriter>(),
      locator<EnvironmentRepository>(),
      locator<ResponseExampleRepository>(),
      locator<RequestScriptsRepository>(),
    ),
  );
  // One for the whole session: the traffic recorder keeps recording after its dialog closes.
  locator.registerLazySingleton<TrafficRecorderViewModel>(
    () => TrafficRecorderViewModel(locator<CreateCollectionFromRecordingUseCase>()),
  );
  // The CORS proxy: the web app's choices (read by the HTTP client for every call) and, on the desktop, the proxy itself,
  // which keeps answering after its dialog closes.
  locator.registerLazySingleton<CorsProxySettingsViewModel>(() => CorsProxySettingsViewModel(SecureCorsProxySettingsStore()));
  locator.registerLazySingleton<CorsProxyServerViewModel>(CorsProxyServerViewModel.new);
  // Finds running emulators and phones with adb / simctl; runs nothing until the device helper asks.
  locator.registerLazySingleton<DeviceDetector>(createSystemDeviceDetector);
  locator.registerFactory<GraphqlExplorerViewModel>(
    () => GraphqlExplorerViewModel(
      locator<ApiClient>(),
      () => locator<BuildVariableResolverUseCase>()(0),
      settings: locator<SettingsRepository>(),
    ),
  );
  locator.registerFactory<RealtimeViewModel>(
    () => RealtimeViewModel(const RealtimeConnector(), () => locator<BuildVariableResolverUseCase>()(0)),
  );
  locator.registerLazySingleton<OdooClient>(() => OdooClient(locator<ApiClient>(), settings: locator<SettingsRepository>()));
  locator.registerLazySingleton<OdooSmartReferenceResolver>(
    () => OdooSmartReferenceResolver(
      locator<ApiClient>(),
      // The app's timeout, proxy and certificate settings, as for every call of a saved request.
      options: () => ToolRequestOptions.resolve(locator<SettingsRepository>(), maxResponseBytes: 8 * 1024 * 1024),
    ),
  );
  locator.registerLazySingleton<OdooDoctor>(() => OdooDoctor(locator<EnvironmentRepository>(), locator<OdooClient>()));
  locator.registerLazySingleton<CreateOdooWorkspaceUseCase>(
    () => CreateOdooWorkspaceUseCase(
      locator<EnvironmentRepository>(),
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<DocumentationRepository>(),
    ),
  );
  locator.registerFactory<OdooStudioViewModel>(
    () => OdooStudioViewModel(
      locator<OdooClient>(),
      locator<EnvironmentRepository>(),
      locator<CreateOdooWorkspaceUseCase>(),
    ),
  );
}

/// The cleanup ledger: the records this session's requests created, and the way to delete them again. In memory only.
void _registerCleanupLedger() {
  locator.registerLazySingleton<CleanupLedger>(
    () => CleanupLedger(
      AppCleanupSender(
        environmentName: () async => (await locator<EnvironmentRepository>().watchActive().first)?.name,
        candidates: locator<ReloginUseCase>().candidates,
        findRequest: locator<RequestRepository>().findById,
        // The normal send path (variables, authentication, History, the console); the production lock is asked by the caller.
        send: (request, variables) async {
          final outcome = await locator<RequestFlowService>().send(request, dataVariables: variables);
          final error = outcome.error;
          if (error != null) throw error;
          return outcome.response ?? (throw StateError('The server sent no response.'));
        },
      ),
    ),
  );
  locator.registerFactory<CleanupSectionViewModel>(
    () => CleanupSectionViewModel(
      findRequest: locator<RequestRepository>().findById,
      candidates: locator<ReloginUseCase>().candidates,
      lastResponse: (requestId) => locator<ResponseHistory>().of(requestId).firstOrNull,
    ),
  );
}

/// Workspace refactoring: find and replace, rename a variable and the unused-variables report. They read and write through
/// the repositories the screens use, so autosave, Git sync and open lists see every change. The undo of the last change
/// is one object for the whole session (memory only), so a dialog opened again still offers it.
void _registerWorkspaceRefactor() {
  locator.registerLazySingleton<WorkspaceReader>(
    () => WorkspaceReader(
      locator<CollectionLoader>(),
      locator<EnvironmentRepository>(),
      locator<GlobalVariableRepository>(),
      locator<RequestScriptsRepository>(),
      locator<ResponseExampleRepository>(),
      locator<DocumentationRepository>(),
      locator<TagRepository>(),
    ),
  );
  locator.registerLazySingleton<RefactorUndoStore>(RefactorUndoStore.new);
  locator.registerLazySingleton<RefactorApplier>(
    () => RefactorApplier(
      locator<WorkspaceReader>(),
      RepositoryRefactorWriter(
        locator<RequestRepository>(),
        locator<RequestScriptsRepository>(),
        locator<ResponseExampleRepository>(),
        locator<CollectionRepository>(),
        locator<CollectionAuthRepository>(),
        locator<CollectionVariableRepository>(),
        locator<DefaultsRepository>(),
        locator<EnvironmentRepository>(),
        locator<GlobalVariableRepository>(),
        locator<DocumentationRepository>(),
        locator<TagRepository>(),
      ),
      // One transaction: a failure rolls every change back, and the autosave hears of one change, not thousands.
      atomically: locator<AppDatabase>().transaction,
    ),
  );
  locator.registerFactory<WorkspaceRefactorViewModel>(
    () => WorkspaceRefactorViewModel(locator<WorkspaceReader>(), locator<RefactorApplier>(), locator<RefactorUndoStore>()),
  );
}

void _registerWorkplace() {
  locator.registerLazySingleton<WorkplaceRepository>(
    () => WorkplaceRepositoryImpl(keepSecretsLocal: () => locator<SafetyPrefs>().keepSecretsLocal),
  );
  locator.registerLazySingleton<WorkplaceViewModel>(
    () => WorkplaceViewModel(
      repository: locator<WorkplaceRepository>(),
      backupService: locator<BackupService>(),
      database: locator<AppDatabase>(),
      shellViewModel: locator<ShellViewModel>(),
    ),
  );
}

void _registerCore(AppDatabase database) {
  locator.registerSingleton<AppDatabase>(database);
  // The console log is resolved eagerly by the ApiClient below, so it must
  // be registered first. CookieJar() on web is the package's no-op
  // WebCookieJar (the browser owns cookies there); native gets StrictCookieJar.
  locator.registerSingleton<RequestConsoleLog>(RequestConsoleLog());
  locator.registerSingleton<CookieJar>(kIsWeb ? CookieJar() : StrictCookieJar());
  locator.registerSingleton<ApiClient>(
    LoggingApiClient(
      DioApiClient(
        cookieJar: locator<CookieJar>(),
        // The web version sends calls through the CORS proxy while it is switched on (Settings > CORS proxy).
        corsProxy: kIsWeb ? () => locator<CorsProxySettingsViewModel>().route() : null,
      ),
      locator<RequestConsoleLog>(),
    ),
  );
}

void _registerCollections() {
  locator.registerLazySingleton<CollectionRepository>(
    () => CollectionRepositoryImpl(locator<AppDatabase>().collectionsDao),
  );
  locator.registerLazySingleton<CollectionOrderRepository>(
    () => CollectionOrderRepositoryImpl(locator<AppDatabase>().collectionsDao),
  );
  locator.registerLazySingleton<CollectionVariableRepository>(
    () => CollectionVariableRepositoryImpl(locator<AppDatabase>().collectionVariablesDao),
  );
  locator.registerLazySingleton<CollectionAuthRepository>(
    () => CollectionAuthRepositoryImpl(locator<AppDatabase>().collectionAuthDao),
  );
  locator.registerLazySingleton<CollectionsViewModel>(
    () => CollectionsViewModel(
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      requestIdFilter: locator<TagFilterViewModel>(),
      orderRepository: locator<CollectionOrderRepository>(),
    ),
  );
  locator.registerFactory<CollectionRunnerViewModel>(
    () => CollectionRunnerViewModel(locator<CollectionRunnerService>()),
  );
}

/// Run history, failure triage and the monitor: records of finished runs, kept on this device only.
void _registerRunTriage() {
  locator.registerLazySingleton<RunRecordRepository>(
    () => RunRecordRepositoryImpl(locator<AppDatabase>().runRecordsDao),
  );
  // One for the whole session: it keeps running while no dialog is open.
  locator.registerLazySingleton<MonitorService>(
    () => MonitorService(
      store: SettingsMonitorConfigStore(locator<AppDatabase>().settingsDao),
      collections: locator<CollectionRepository>(),
      records: locator<RunRecordRepository>(),
      runner: MonitorRunner(
        runner: locator<CollectionRunnerService>(),
        collections: locator<CollectionRepository>(),
        environments: locator<EnvironmentRepository>(),
        resolver: locator<BuildVariableResolverUseCase>(),
        records: locator<RunRecordRepository>(),
        productionWords: () => locator<SafetyPrefs>().extraWords,
        productionHosts: () => locator<SafetyPrefs>().productionHosts,
      ),
    ),
  );
}

void _registerRequestBuilder() {
  locator.registerLazySingleton<RequestRepository>(() => RequestRepositoryImpl(locator<AppDatabase>().requestsDao));
  locator.registerLazySingleton<RequestScriptsRepository>(
    () => RequestScriptsRepositoryImpl(locator<AppDatabase>().requestScriptsDao),
  );
  locator.registerLazySingleton<ResponseExampleRepository>(
    () => ResponseExampleRepositoryImpl(locator<AppDatabase>().responseExamplesDao),
  );
  locator.registerLazySingleton<OAuth2TokenService>(
    () => OAuth2TokenService(locator<ApiClient>(), settings: locator<SettingsRepository>()),
  );
  locator.registerLazySingleton<BuildVariableResolverUseCase>(
    () => BuildVariableResolverUseCase(
      locator<CollectionVariableRepository>(),
      locator<EnvironmentRepository>(),
      locator<GlobalVariableRepository>(),
      locator<DefaultsRepository>(),
    ),
  );
  // Self-renewing auth: the OAuth 2.0 token is kept valid before every send, and a rejected request can run
  // the collection's login request and be sent once more.
  locator.registerLazySingleton<OAuth2TokenStore>(
    () => RepositoryOAuth2TokenStore(
      locator<RequestRepository>(),
      locator<CollectionAuthRepository>(),
      locator<DefaultsRepository>(),
    ),
  );
  locator.registerLazySingleton<OAuth2TokenManager>(
    () => OAuth2TokenManager(locator<OAuth2TokenService>(), locator<OAuth2TokenStore>()),
  );
  locator.registerLazySingleton<ReloginUseCase>(
    () => ReloginUseCase(
      locator<RequestRepository>(),
      locator<CollectionAuthRepository>(),
      locator<RunRequestScriptsUseCase>(),
      collections: locator<CollectionRepository>(),
      defaults: locator<ResolveRequestDefaultsUseCase>(),
    ),
  );
  locator.registerLazySingleton<SendRequestUseCase>(
    () => SendRequestUseCase(
      locator<ApiClient>(),
      locator<BuildVariableResolverUseCase>(),
      locator<HistoryRepository>(),
      locator<CollectionAuthRepository>(),
      locator<SettingsRepository>(),
      locator<RequestSettingsRepository>(),
      const RequestSpecBuilder(),
      locator<ResolveRequestDefaultsUseCase>(),
      RenewRequestAuthUseCase(locator<OAuth2TokenManager>()),
      locator<ReloginUseCase>(),
      // {{xmlid:...}} / {{ref:...}} in an Odoo request are looked up on the server it goes to, when it is sent.
      locator<OdooSmartReferenceResolver>(),
    ),
  );
  locator.registerLazySingleton<GenerateCodeSnippetUseCase>(
    () => GenerateCodeSnippetUseCase(
      locator<BuildVariableResolverUseCase>(),
      locator<CollectionAuthRepository>(),
      settings: locator<SettingsRepository>(),
      requestSettings: locator<RequestSettingsRepository>(),
      defaults: locator<ResolveRequestDefaultsUseCase>(),
    ),
  );
  // Retry, poll until, fetch all pages, run if: the editor and the collection runner send through it. Each try after
  // the first is announced in the console.
  locator.registerLazySingleton<RequestFlowService>(
    () => RequestFlowService(
      locator<RequestSettingsRepository>(),
      locator<SendRequestUseCase>(),
      AppFlowEnvironment(locator<BuildVariableResolverUseCase>(), locator<EnvironmentRepository>()),
      onNote: locator<RequestConsoleLog>().addNote,
      // The cleanup ledger records what a request with "Clean up what this request creates" made.
      onSent: locator<CleanupLedger>().recordSend,
    ),
  );
  locator.registerLazySingleton<CollectionRunnerService>(
    () => CollectionRunnerService.withFlow(
      locator<RequestRepository>(),
      locator<SendRequestUseCase>(),
      locator<RunRequestScriptsUseCase>(),
      locator<CollectionRepository>(),
      locator<RequestFlowService>(),
    ),
  );
  locator.registerLazySingleton<ListVariablesUseCase>(
    () => ListVariablesUseCase(
      locator<CollectionVariableRepository>(),
      locator<EnvironmentRepository>(),
      locator<GlobalVariableRepository>(),
      locator<DefaultsRepository>(),
    ),
  );
  locator.registerFactory<VariableScope>(
    () => VariableScope(locator<ListVariablesUseCase>(), refreshOn: locator<EnvironmentsViewModel>()),
  );
  locator.registerFactory<RequestBuilderViewModel>(
    () => RequestBuilderViewModel(
      locator<RequestRepository>(),
      locator<SendRequestUseCase>(),
      locator<GenerateCodeSnippetUseCase>(),
      locator<RunRequestScriptsUseCase>(),
      locator<RequestFlowService>(),
    ),
  );
  locator.registerFactory<RequestOAuth2ViewModel>(
    () => RequestOAuth2ViewModel(
      locator<OAuth2TokenService>(),
      locator<BuildVariableResolverUseCase>(),
      locator<OAuth2TokenManager>(),
    ),
  );
  locator.registerFactory<ReloginSectionViewModel>(
    () => ReloginSectionViewModel(locator<ReloginUseCase>(), locator<SendRequestUseCase>()),
  );
  locator.registerFactory<InheritedOAuth2StatusViewModel>(
    () => InheritedOAuth2StatusViewModel(locator<OAuth2TokenManager>(), locator<BuildVariableResolverUseCase>()),
  );
  locator.registerFactory<ResponseExamplesViewModel>(
    () => ResponseExamplesViewModel(locator<ResponseExampleRepository>()),
  );
}

void _registerScripting() {
  // Recorded response baselines (local to this device) and the guard that holds a request to its baseline in runs.
  locator.registerLazySingleton<RequestBaselineRepository>(
    () => RequestBaselineRepositoryImpl(locator<AppDatabase>().requestBaselinesDao),
  );
  locator.registerLazySingleton<BaselineGuard>(
    () => BaselineGuard(locator<RequestBaselineRepository>(), locator<RequestSettingsRepository>()),
  );
  locator.registerLazySingleton<RunRequestScriptsUseCase>(
    () => RunRequestScriptsUseCase(
      locator<RequestScriptsRepository>(),
      locator<BuildVariableResolverUseCase>(),
      locator<EnvironmentRepository>(),
      locator<GlobalVariableRepository>(),
      const AssertionEvaluator(),
      locator<ResolveRequestDefaultsUseCase>(),
      locator<BaselineGuard>(),
    ),
  );
  locator.registerFactory<RequestScriptsViewModel>(() => RequestScriptsViewModel(locator<RequestScriptsRepository>()));
  locator.registerLazySingleton<ExportBaselinesUseCase>(
    () => ExportBaselinesUseCase(locator<RequestBaselineRepository>(), locator<CollectionLoader>()),
  );
  // "Generate tests from OpenAPI…": a Tests folder of requests with assertions written into a collection.
  locator.registerLazySingleton<GenerateOpenApiTestsUseCase>(
    () => GenerateOpenApiTestsUseCase(
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<RequestScriptsRepository>(),
      locator<RequestSettingsRepository>(),
      locator<CollectionVariableRepository>(),
    ),
  );
}

/// What a collection and its folders pass down to their requests (headers, auth, variables, tests).
void _registerDefaults() {
  locator.registerLazySingleton<DefaultsRepository>(() => DefaultsRepositoryImpl(locator<AppDatabase>()));
  locator.registerLazySingleton<ResolveRequestDefaultsUseCase>(
    () => ResolveRequestDefaultsUseCase(locator<DefaultsRepository>()),
  );
  locator.registerFactory<InheritedDefaultsViewModel>(
    () => InheritedDefaultsViewModel(locator<ResolveRequestDefaultsUseCase>()),
  );
  locator.registerFactory<DefaultsViewModel>(
    () => DefaultsViewModel(
      locator<DefaultsRepository>(),
      locator<CollectionAuthRepository>(),
      locator<CollectionVariableRepository>(),
    ),
  );
}

void _registerEnvironments() {
  locator.registerLazySingleton<EnvironmentRepository>(
    () => EnvironmentRepositoryImpl(locator<AppDatabase>().environmentsDao),
  );
  locator.registerLazySingleton<GlobalVariableRepository>(
    () => GlobalVariableRepositoryImpl(locator<AppDatabase>().globalVariablesDao),
  );
  locator.registerLazySingleton<EnvironmentsViewModel>(
    () => EnvironmentsViewModel(locator<EnvironmentRepository>(), locator<GlobalVariableRepository>()),
  );
}

void _registerHistory() {
  // What History keeps (Settings > History); it loads itself on first use.
  locator.registerLazySingleton<HistoryPrefs>(HistoryPrefs.new);
  locator.registerLazySingleton<HistoryRepository>(
    () => HistoryRepositoryImpl(
      locator<AppDatabase>().historyDao,
      policy: locator<HistoryPrefs>(),
      context: RepositoryHistoryContextSource(
        collections: locator<CollectionRepository>(),
        environments: locator<EnvironmentRepository>(),
        globals: locator<GlobalVariableRepository>(),
        collectionAuth: locator<CollectionAuthRepository>(),
      ),
    ),
  );
  locator.registerLazySingleton<HistoryViewModel>(() => HistoryViewModel(locator<HistoryRepository>()));
}

void _registerCookies() {
  locator.registerLazySingleton<CookieRepository>(() => CookieRepositoryImpl(locator<CookieJar>()));
  locator.registerFactory<CookiesViewModel>(() => CookiesViewModel(locator<CookieRepository>()));
}

void _registerShell() {
  locator.registerLazySingleton<LayoutPrefs>(LayoutPrefs.new);
  locator.registerLazySingleton<ShellViewModel>(() {
    final shell = ShellViewModel(locator<RequestRepository>());
    // A closed or deleted tab takes the responses kept for "Compare" with it.
    shell.addListener(() => locator<ResponseHistory>().retainOnly(shell.openRequestIds));
    return shell;
  });
}

void _registerSettings() {
  locator.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(locator<AppDatabase>().settingsDao, SecureProxyPasswordStore()),
  );
  locator.registerLazySingleton<RequestSettingsRepository>(
    () => RequestSettingsRepositoryImpl(locator<AppDatabase>().requestSettingsDao),
  );
  locator.registerLazySingleton<SettingsViewModel>(() => SettingsViewModel(locator<SettingsRepository>()));
  locator.registerFactory<RequestSettingsViewModel>(
    () => RequestSettingsViewModel(locator<RequestSettingsRepository>(), locator<SettingsRepository>()),
  );
  locator.registerFactory<RequestFlowViewModel>(() => RequestFlowViewModel(locator<RequestSettingsRepository>()));
}

void _registerDocumentation() {
  locator.registerLazySingleton<DocumentationRepository>(
    () => DocumentationRepositoryImpl(locator<AppDatabase>().entityDocsDao),
  );
  locator.registerLazySingleton<TagRepository>(() => TagRepositoryImpl(locator<AppDatabase>().entityTagsDao));
  locator.registerLazySingleton<BuildApiDocsUseCase>(
    () => BuildApiDocsUseCase(
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<ResponseExampleRepository>(),
      locator<CollectionVariableRepository>(),
      locator<CollectionAuthRepository>(),
      locator<DocumentationRepository>(),
      locator<TagRepository>(),
      locator<DefaultsRepository>(),
    ),
  );
  locator.registerLazySingleton<TagFilterViewModel>(
    () => TagFilterViewModel(locator<TagRepository>(), locator<CollectionRepository>(), locator<RequestRepository>()),
  );
  locator.registerFactoryParam<EntityDocsViewModel, EntityKind, int>(
    (kind, id) => EntityDocsViewModel(locator<DocumentationRepository>(), kind, id),
  );
  locator.registerFactoryParam<TagsViewModel, EntityKind, int>(
    (kind, id) => TagsViewModel(locator<TagRepository>(), kind, id),
  );
  locator.registerFactory<AllTagsViewModel>(() => AllTagsViewModel(locator<TagRepository>()));
  locator.registerFactory<CollectionDocsViewModel>(() => CollectionDocsViewModel(locator<BuildApiDocsUseCase>()));
}

void _registerImportExport() {
  locator.registerLazySingleton<ImportedCollectionWriter>(
    () => ImportedCollectionWriter(
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<CollectionVariableRepository>(),
      locator<CollectionAuthRepository>(),
    ),
  );
  locator.registerLazySingleton<CollectionLoader>(
    () => CollectionLoader(
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<CollectionVariableRepository>(),
      locator<CollectionAuthRepository>(),
      locator<DefaultsRepository>(),
    ),
  );
  locator.registerLazySingleton<BackupService>(
    () => BackupService(
      locator<CollectionLoader>(),
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<CollectionVariableRepository>(),
      locator<CollectionAuthRepository>(),
      locator<RequestScriptsRepository>(),
      locator<ResponseExampleRepository>(),
      locator<EnvironmentRepository>(),
      locator<GlobalVariableRepository>(),
      locator<RequestSettingsRepository>(),
      locator<DocumentationRepository>(),
      locator<TagRepository>(),
      locator<GitStateStore>(),
      locator<DefaultsRepository>(),
    ),
  );

  locator.registerLazySingleton<ImportPostmanCollectionUseCase>(
    () => ImportPostmanCollectionUseCase(
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<CollectionVariableRepository>(),
      locator<CollectionAuthRepository>(),
      locator<RequestScriptsRepository>(),
      locator<DefaultsRepository>(),
    ),
  );
  locator.registerLazySingleton<ImportPostmanEnvironmentUseCase>(
    () => ImportPostmanEnvironmentUseCase(locator<EnvironmentRepository>(), locator<GlobalVariableRepository>()),
  );
  locator.registerLazySingleton<ExportPostmanCollectionUseCase>(
    () => ExportPostmanCollectionUseCase(
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<CollectionVariableRepository>(),
      locator<CollectionAuthRepository>(),
      locator<DefaultsRepository>(),
    ),
  );
  locator.registerLazySingleton<ImportCurlUseCase>(() => ImportCurlUseCase(locator<RequestRepository>()));
  locator.registerLazySingleton<ImportOpenApiUseCase>(
    () => ImportOpenApiUseCase(
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<CollectionVariableRepository>(),
      locator<EnvironmentRepository>(),
    ),
  );
  locator.registerLazySingleton<ImportInsomniaUseCase>(
    () => ImportInsomniaUseCase(
      locator<ImportedCollectionWriter>(),
      locator<CollectionRepository>(),
      locator<EnvironmentRepository>(),
    ),
  );
  locator.registerLazySingleton<ImportHarUseCase>(
    // "Clean up" writes the clean collection the way the traffic recorder does: its environment, examples and checks too.
    () => ImportHarUseCase(locator<ImportedCollectionWriter>(), recorded: locator<CreateCollectionFromRecordingUseCase>()),
  );
  locator.registerLazySingleton<ImportCurlScriptUseCase>(
    () => ImportCurlScriptUseCase(locator<ImportedCollectionWriter>()),
  );
  locator.registerLazySingleton<ExportOpenApiUseCase>(() => ExportOpenApiUseCase(locator<CollectionLoader>()));
  locator.registerLazySingleton<ExportCurlScriptUseCase>(
    () => ExportCurlScriptUseCase(locator<CollectionLoader>(), locator<GenerateCodeSnippetUseCase>()),
  );
  locator.registerLazySingleton<ExportBackupUseCase>(() => ExportBackupUseCase(locator<BackupService>()));
  locator.registerLazySingleton<RestoreBackupUseCase>(() => RestoreBackupUseCase(locator<BackupService>()));
  locator.registerLazySingleton<ImportAnyUseCase>(
    () => ImportAnyUseCase(
      locator<ImportPostmanCollectionUseCase>(),
      locator<ImportOpenApiUseCase>(),
      locator<ImportInsomniaUseCase>(),
      locator<ImportHarUseCase>(),
      locator<ImportCurlScriptUseCase>(),
      locator<RestoreBackupUseCase>(),
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      importPostmanEnvironment: locator<ImportPostmanEnvironmentUseCase>(),
    ),
  );

  locator.registerFactory<ImportExportViewModel>(
    () => ImportExportViewModel(
      locator<ImportPostmanCollectionUseCase>(),
      locator<ImportCurlUseCase>(),
      locator<ExportPostmanCollectionUseCase>(),
      locator<ImportOpenApiUseCase>(),
    ),
  );
  locator.registerFactory<ImportAnyViewModel>(() => ImportAnyViewModel(locator<ImportAnyUseCase>()));
  locator.registerFactory<ExportCollectionViewModel>(
    () => ExportCollectionViewModel(locator<ExportOpenApiUseCase>(), locator<ExportCurlScriptUseCase>()),
  );
  locator.registerFactory<BackupViewModel>(
    () => BackupViewModel(locator<ExportBackupUseCase>(), locator<RestoreBackupUseCase>()),
  );
}

void _registerGitSync() {
  locator.registerLazySingleton<GitCredentialsStore>(() => SecureGitCredentialsStore());
  locator.registerLazySingleton<GitHostClient>(() => GitHubHostClient(locator<GitCredentialsStore>()));
  locator.registerLazySingleton<GitLinkRepository>(() => GitLinkRepositoryImpl(locator<AppDatabase>().gitLinksDao));
  locator.registerLazySingleton<EntityUidRegistry>(() => EntityUidRegistry(locator<AppDatabase>().entityUidsDao));
  locator.registerLazySingleton<LocalCollectionStore>(
    () => LocalCollectionStoreImpl(locator<AppDatabase>(), locator<EntityUidRegistry>()),
  );
  // Lets a workspace file carry each linked collection's Git link (see BackupService).
  locator.registerLazySingleton<GitStateStore>(() => DriftGitStateStore(locator<AppDatabase>()));
  locator.registerLazySingleton<SyncEngine>(
    () => SyncEngine(locator<GitHostClient>(), locator<LocalCollectionStore>()),
  );

  locator.registerLazySingleton<GitSaveTokenUseCase>(
    () => GitSaveTokenUseCase(locator<GitCredentialsStore>(), locator<GitHostClient>()),
  );
  locator.registerLazySingleton<GitDiscoverUseCase>(
    () => GitDiscoverUseCase(locator<GitHostClient>(), locator<SyncEngine>()),
  );
  locator.registerLazySingleton<GitConnectUseCase>(
    () => GitConnectUseCase(locator<GitLinkRepository>(), locator<GitHostClient>(), locator<LocalCollectionStore>()),
  );
  locator.registerLazySingleton<GitCloneUseCase>(
    () => GitCloneUseCase(
      locator<GitHostClient>(),
      locator<LocalCollectionStore>(),
      locator<GitLinkRepository>(),
      locator<SyncEngine>(),
    ),
  );
  locator.registerLazySingleton<GitStatusUseCase>(
    () => GitStatusUseCase(locator<GitLinkRepository>(), locator<GitHostClient>(), locator<SyncEngine>()),
  );
  locator.registerLazySingleton<GitCommitPushUseCase>(
    () => GitCommitPushUseCase(locator<GitLinkRepository>(), locator<GitHostClient>(), locator<SyncEngine>()),
  );
  locator.registerLazySingleton<GitPullUseCase>(
    () => GitPullUseCase(
      locator<GitLinkRepository>(),
      locator<LocalCollectionStore>(),
      locator<GitHostClient>(),
      locator<SyncEngine>(),
    ),
  );
  locator.registerLazySingleton<GitDiscardUseCase>(
    () => GitDiscardUseCase(locator<GitLinkRepository>(), locator<LocalCollectionStore>(), locator<SyncEngine>()),
  );
  locator.registerLazySingleton<GitListBranchesUseCase>(
    () => GitListBranchesUseCase(locator<GitLinkRepository>(), locator<GitHostClient>()),
  );
  locator.registerLazySingleton<GitCreateBranchUseCase>(
    () => GitCreateBranchUseCase(locator<GitLinkRepository>(), locator<GitHostClient>()),
  );
  locator.registerLazySingleton<GitSwitchBranchUseCase>(
    () => GitSwitchBranchUseCase(
      locator<GitLinkRepository>(),
      locator<LocalCollectionStore>(),
      locator<GitHostClient>(),
      locator<SyncEngine>(),
    ),
  );
  locator.registerLazySingleton<GitContributorsUseCase>(
    () => GitContributorsUseCase(locator<GitLinkRepository>(), locator<GitHostClient>()),
  );
  locator.registerLazySingleton<GitHistoryUseCase>(
    () => GitHistoryUseCase(locator<GitLinkRepository>(), locator<GitHostClient>()),
  );
  locator.registerLazySingleton<GitUpdateLinkSettingsUseCase>(
    () => GitUpdateLinkSettingsUseCase(locator<GitLinkRepository>()),
  );
  locator.registerLazySingleton<GitDisconnectUseCase>(() => GitDisconnectUseCase(locator<GitLinkRepository>()));

  locator.registerLazySingleton<LinkedCollectionsViewModel>(
    () => LinkedCollectionsViewModel(locator<GitLinkRepository>()),
  );
  locator.registerFactory<GitSyncViewModel>(
    () => GitSyncViewModel(
      credentials: locator<GitCredentialsStore>(),
      saveTokenUseCase: locator<GitSaveTokenUseCase>(),
      links: locator<GitLinkRepository>(),
      statusUseCase: locator<GitStatusUseCase>(),
      connectUseCase: locator<GitConnectUseCase>(),
      commitPushUseCase: locator<GitCommitPushUseCase>(),
      pullUseCase: locator<GitPullUseCase>(),
      discardUseCase: locator<GitDiscardUseCase>(),
      historyUseCase: locator<GitHistoryUseCase>(),
      listBranchesUseCase: locator<GitListBranchesUseCase>(),
      createBranchUseCase: locator<GitCreateBranchUseCase>(),
      switchBranchUseCase: locator<GitSwitchBranchUseCase>(),
      contributorsUseCase: locator<GitContributorsUseCase>(),
      updateLinkSettingsUseCase: locator<GitUpdateLinkSettingsUseCase>(),
      disconnectUseCase: locator<GitDisconnectUseCase>(),
    ),
  );
  locator.registerFactory<GitCloneViewModel>(
    () => GitCloneViewModel(
      credentials: locator<GitCredentialsStore>(),
      saveTokenUseCase: locator<GitSaveTokenUseCase>(),
      discoverUseCase: locator<GitDiscoverUseCase>(),
      cloneUseCase: locator<GitCloneUseCase>(),
    ),
  );
}
