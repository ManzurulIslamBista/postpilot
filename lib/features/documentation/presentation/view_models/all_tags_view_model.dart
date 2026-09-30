import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/repositories/tag_repository.dart';

/// Every tag in use, for suggestions while typing a new one.
final class AllTagsViewModel with ChangeNotifier {
  AllTagsViewModel(TagRepository repository) {
    _subscription = repository.watchAllTags().listen((value) {
      if (listEquals(value, tags)) return;
      tags = value;
      notifyListeners();
    });
  }

  List<String> tags = const [];

  late final StreamSubscription<List<String>> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
