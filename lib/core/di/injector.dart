import '../layout/layout_prefs.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/dio_api_client.dart';
import '../network/logging_api_client.dart';
import '../network/strict_cookie_jar.dart';
import '../../features/collections/data/repositories/collection_auth_repository_impl.dart';
import '../../features/collections/data/repositories/collection_repository_impl.dart';
import '../../features/collections/data/repositories/collection_variable_repository_impl.dart';
import '../../features/collections/domain/repositories/collection_auth_repository.dart';
import '../../features/collections/domain/repositories/collection_repository.dart';
import '../../features/collections/domain/repositories/collection_variable_repository.dart';
import '../../features/collections/presentation/view_models/collection_runner_view_model.dart';
import '../../features/collections/presentation/view_models/collections_view_model.dart';
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
import '../../features/dart_codegen/domain/usecases/build_api_layer_usecase.dart';
import '../../features/graphql/presentation/graphql_explorer_view_model.dart';
import '../../features/import_export/domain/usecases/refresh_openapi_usecase.dart';
import '../../features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import '../../features/mock_server/presentation/mock_server_view_model.dart';
import '../../features/odoo/data/odoo_client.dart';
import '../../features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import '../../features/odoo/presentation/view_models/odoo_studio_view_model.dart';
import '../../features/realtime/data/realtime_session.dart';
import '../../features/realtime/presentation/realtime_view_model.dart';
import '../../features/response_tools/domain/services/response_history.dart';
import '../../features/templates/domain/usecases/add_starter_template_usecase.dart';
import '../../features/tour/presentation/tour_dialog.dart';
import '../../features/safety/data/safety_prefs.dart';
import '../../features/safety/domain/services/production_guard.dart';
import '../../features/dart_codegen/presentation/view_models/api_layer_view_model.dart';
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
import '../../features/history/domain/repositories/history_repository.dart';
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
import '../../features/request_builder/presentation/view_models/request_builder_view_model.dart';
import '../../features/request_builder/presentation/view_models/request_oauth2_view_model.dart';
import '../../features/request_builder/presentation/view_models/response_examples_view_model.dart';
import '../../features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../../features/scripting/presentation/view_models/request_scripts_view_model.dart';
import '../../features/settings/data/repositories/request_settings_repository_impl.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/data/secure_proxy_password_store.dart';
import '../../features/settings/domain/repositories/request_settings_repository.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';
import '../../features/settings/presentation/view_models/request_settings_view_model.dart';
import '../../features/settings/presentation/view_models/settings_view_model.dart';
import '../../features/shell/presentation/shell_view_model.dart';
import '../../features/workplace/data/repositories/workplace_repository_impl.dart';
import '../../features/workplace/domain/repositories/workplace_repository.dart';
import '../../features/workplace/presentation/view_models/workplace_view_model.dart';

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
  _registerRequestBuilder();
  _registerScripting();
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
}

/// Developer tools: generators and helpers that sit beside the request builder.
void _registerDevTools() {
  locator.registerLazySingleton<BuildApiLayerUseCase>(
    () => BuildApiLayerUseCase(locator<CollectionLoader>(), locator<ResponseExampleRepository>()),
  );
  locator.registerFactory<ApiLayerViewModel>(() => ApiLayerViewModel(locator<BuildApiLayerUseCase>()));
  locator.registerLazySingleton<ResponseHistory>(ResponseHistory.new);
  locator.registerLazySingleton<SafetyPrefs>(SafetyPrefs.new);
  locator.registerLazySingleton<ProductionGuard>(
    () => ProductionGuard(
      locator<EnvironmentRepository>(),
      locator<SafetyPrefs>(),
      // Resolves {{baseUrl}} the way a send does, so the production-host list sees the real host.
      (r) async => (await locator<BuildVariableResolverUseCase>()(r.collectionId)).resolve(r.url),
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
    LoggingApiClient(DioApiClient(cookieJar: locator<CookieJar>()), locator<RequestConsoleLog>()),
  );
}

void _registerCollections() {
  locator.registerLazySingleton<CollectionRepository>(
    () => CollectionRepositoryImpl(locator<AppDatabase>().collectionsDao),
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
    ),
  );
  locator.registerFactory<CollectionRunnerViewModel>(
    () => CollectionRunnerViewModel(locator<CollectionRunnerService>()),
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
    ),
  );
  locator.registerLazySingleton<GenerateCodeSnippetUseCase>(
    () => GenerateCodeSnippetUseCase(
      locator<BuildVariableResolverUseCase>(),
      locator<CollectionAuthRepository>(),
      settings: locator<SettingsRepository>(),
      requestSettings: locator<RequestSettingsRepository>(),
    ),
  );
  locator.registerLazySingleton<CollectionRunnerService>(
    () => CollectionRunnerService(
      locator<RequestRepository>(),
      locator<SendRequestUseCase>(),
      locator<RunRequestScriptsUseCase>(),
    ),
  );
  locator.registerLazySingleton<ListVariablesUseCase>(
    () => ListVariablesUseCase(
      locator<CollectionVariableRepository>(),
      locator<EnvironmentRepository>(),
      locator<GlobalVariableRepository>(),
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
    ),
  );
  locator.registerFactory<RequestOAuth2ViewModel>(
    () => RequestOAuth2ViewModel(locator<OAuth2TokenService>(), locator<BuildVariableResolverUseCase>()),
  );
  locator.registerFactory<ResponseExamplesViewModel>(
    () => ResponseExamplesViewModel(locator<ResponseExampleRepository>()),
  );
}

void _registerScripting() {
  locator.registerLazySingleton<RunRequestScriptsUseCase>(
    () => RunRequestScriptsUseCase(
      locator<RequestScriptsRepository>(),
      locator<BuildVariableResolverUseCase>(),
      locator<EnvironmentRepository>(),
      locator<GlobalVariableRepository>(),
    ),
  );
  locator.registerFactory<RequestScriptsViewModel>(() => RequestScriptsViewModel(locator<RequestScriptsRepository>()));
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
  locator.registerLazySingleton<HistoryRepository>(() => HistoryRepositoryImpl(locator<AppDatabase>().historyDao));
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
    ),
  );

  locator.registerLazySingleton<ImportPostmanCollectionUseCase>(
    () => ImportPostmanCollectionUseCase(
      locator<CollectionRepository>(),
      locator<RequestRepository>(),
      locator<CollectionVariableRepository>(),
      locator<CollectionAuthRepository>(),
      locator<RequestScriptsRepository>(),
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
  locator.registerLazySingleton<ImportHarUseCase>(() => ImportHarUseCase(locator<ImportedCollectionWriter>()));
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
