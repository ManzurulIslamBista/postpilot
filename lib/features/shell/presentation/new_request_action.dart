import '../../collections/presentation/view_models/collections_view_model.dart';
import 'shell_view_model.dart';

/// Where [createNewRequest] put the request it made.
typedef NewRequestPlacement = ({int collectionId, int requestId, bool createdCollection});

/// What "New request" does, from the button, Ctrl+N and the command palette alike.
///
/// The request goes beside the active tab, so working in one collection keeps new requests there. With no tab open
/// it goes into the first collection, and on a fresh install, where there is none, into a new "My collection":
/// the first thing a new user presses must work, not ask them to find out how to make a collection first.
Future<NewRequestPlacement> createNewRequest(CollectionsViewModel collections, ShellViewModel shell) async {
  final beside = await shell.selectedRequestLocation();
  final ensured = beside == null ? await collections.ensureCollection() : null;
  final collectionId = beside?.collectionId ?? ensured!.id;
  final requestId = await collections.createRequest(collectionId, folderId: beside?.folderId);
  return (collectionId: collectionId, requestId: requestId, createdCollection: ensured?.created ?? false);
}
