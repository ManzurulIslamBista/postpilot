import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/repositories/git_link_repository.dart';

final class LinkedCollectionsViewModel with ChangeNotifier {
  late final StreamSubscription<Set<int>> _subscription;

  LinkedCollectionsViewModel(GitLinkRepository repository) {
    _subscription = repository.watchLinkedCollectionIds().listen((ids) {
      linkedIds = ids;
      notifyListeners();
    });
  }

  Set<int> linkedIds = const {};

  bool isLinked(int collectionId) => linkedIds.contains(collectionId);

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
