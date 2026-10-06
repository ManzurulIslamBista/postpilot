import '../../../core/di/injector.dart';
import '../../collections/domain/entities/collection_entity.dart';
import '../../collections/domain/repositories/collection_repository.dart';
import '../../collections/presentation/view_models/collection_runner_view_model.dart';
import '../../environments/domain/repositories/environment_repository.dart';
import '../../request_builder/domain/repositories/request_repository.dart';
import '../domain/repositories/run_record_repository.dart';
import 'run_triage_controller.dart';

/// What a run record needs to know, read from the app's repositories. Anything that is not registered (a test that
/// wires only what it needs) or cannot be read is left blank: the triage works without it.
Future<RunContext> loadRunContext(int collectionId) async {
  var collectionName = '';
  var environmentName = '';
  var folders = const <FolderEntity>[];
  if (locator.isRegistered<CollectionRepository>()) {
    final collections = locator<CollectionRepository>();
    try {
      collectionName = (await collections.watchCollections().first).where((c) => c.id == collectionId).firstOrNull?.name ?? '';
      folders = await collections.watchFolders(collectionId).first;
    } catch (_) {}
  }
  if (locator.isRegistered<EnvironmentRepository>()) {
    try {
      environmentName = (await locator<EnvironmentRepository>().watchActive().first)?.name ?? '';
    } catch (_) {}
  }
  return RunContext(
    collectionName: collectionName,
    environmentName: environmentName,
    folders: folders,
    urlOf: (id) async => locator.isRegistered<RequestRepository>() ? (await locator<RequestRepository>().findById(id))?.url : null,
  );
}

/// The controller the runner dialog uses: stores finished runs in the run history when the app has one.
RunTriageController createRunTriageController(CollectionRunnerViewModel runner, int collectionId) => RunTriageController(
      runner: runner,
      collectionId: collectionId,
      records: locator.isRegistered<RunRecordRepository>() ? locator<RunRecordRepository>() : null,
      context: () => loadRunContext(collectionId),
    );
