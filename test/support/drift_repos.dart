import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/collections/data/repositories/collection_auth_repository_impl.dart';
import 'package:postpilot/features/collections/data/repositories/collection_repository_impl.dart';
import 'package:postpilot/features/collections/data/repositories/collection_variable_repository_impl.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/defaults/data/defaults_repository_impl.dart';
import 'package:postpilot/features/defaults/domain/repositories/defaults_repository.dart';
import 'package:postpilot/features/documentation/data/repositories/documentation_repository_impl.dart';
import 'package:postpilot/features/documentation/data/repositories/tag_repository_impl.dart';
import 'package:postpilot/features/documentation/domain/repositories/documentation_repository.dart';
import 'package:postpilot/features/documentation/domain/repositories/tag_repository.dart';
import 'package:postpilot/features/environments/data/repositories/environment_repository_impl.dart';
import 'package:postpilot/features/environments/data/repositories/global_variable_repository_impl.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/request_builder/data/repositories/request_repository_impl.dart';
import 'package:postpilot/features/request_builder/data/repositories/request_scripts_repository_impl.dart';
import 'package:postpilot/features/request_builder/data/repositories/response_example_repository_impl.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/settings/data/repositories/request_settings_repository_impl.dart';
import 'package:postpilot/features/settings/domain/repositories/request_settings_repository.dart';
import 'in_memory_import_export_fakes.dart';

/// The real repositories over a real (in-memory SQLite) database, wired the way the
/// injector wires them. Shared by the tests that need actual rows rather than fakes.
final class DriftRepos implements RepositoryBundle, DefaultsRepositoryHolder {
  DriftRepos(AppDatabase database)
      : defaultsRepository = DefaultsRepositoryImpl(database),
        collectionRepository = CollectionRepositoryImpl(database.collectionsDao),
        requestRepository = RequestRepositoryImpl(database.requestsDao),
        collectionVariableRepository = CollectionVariableRepositoryImpl(database.collectionVariablesDao),
        collectionAuthRepository = CollectionAuthRepositoryImpl(database.collectionAuthDao),
        scriptsRepository = RequestScriptsRepositoryImpl(database.requestScriptsDao),
        exampleRepository = ResponseExampleRepositoryImpl(database.responseExamplesDao),
        environmentRepository = EnvironmentRepositoryImpl(database.environmentsDao),
        globalVariableRepository = GlobalVariableRepositoryImpl(database.globalVariablesDao),
        requestSettingsRepository = RequestSettingsRepositoryImpl(database.requestSettingsDao),
        documentationRepository = DocumentationRepositoryImpl(database.entityDocsDao),
        tagRepository = TagRepositoryImpl(database.entityTagsDao);

  @override
  final DefaultsRepository defaultsRepository;
  @override
  final CollectionRepository collectionRepository;
  @override
  final RequestRepository requestRepository;
  @override
  final CollectionVariableRepository collectionVariableRepository;
  @override
  final CollectionAuthRepository collectionAuthRepository;
  @override
  final RequestScriptsRepository scriptsRepository;
  @override
  final ResponseExampleRepository exampleRepository;
  @override
  final EnvironmentRepository environmentRepository;
  @override
  final GlobalVariableRepository globalVariableRepository;
  @override
  final RequestSettingsRepository requestSettingsRepository;
  @override
  final DocumentationRepository documentationRepository;
  @override
  final TagRepository tagRepository;
}
