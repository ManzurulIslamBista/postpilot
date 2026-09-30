import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/entity_kind.dart';
import '../../domain/repositories/tag_repository.dart';
import '../../domain/services/tag_normalizer.dart';

/// Backs the tag chips of one collection, folder or request. Changes show at
/// once and are written straight away.
final class TagsViewModel with ChangeNotifier {
  final TagRepository _repository;
  final EntityKind kind;
  final int localId;

  TagsViewModel(this._repository, this.kind, this.localId) {
    _subscription = _repository.watchTags(kind, localId).listen(_onStored);
  }

  List<String> tags = const [];
  String? saveError;

  late final StreamSubscription<List<String>> _subscription;
  int _pendingWrites = 0;
  bool _disposed = false;

  Future<void> add(String tag) => _replace(TagNormalizer.normalise([...tags, tag]));

  Future<void> remove(String tag) => _replace([
        for (final existing in tags)
          if (!TagNormalizer.same(existing, tag)) existing,
      ]);

  Future<void> _replace(List<String> next) async {
    if (listEquals(next, tags)) return;
    final previous = tags;
    tags = next;
    notifyListeners();
    _pendingWrites++;
    try {
      await _repository.setTags(kind, localId, next);
      saveError = null;
    } catch (e) {
      if (identical(tags, next)) tags = previous;
      saveError = 'Could not save the tags: $e';
      if (!_disposed) notifyListeners();
    } finally {
      _pendingWrites--;
    }
  }

  /// While a write is in flight the stored list is older than what is shown,
  /// so it is ignored rather than allowed to flicker the chips back.
  void _onStored(List<String> stored) {
    if (_pendingWrites > 0) return;
    if (!listEquals(stored, tags)) {
      tags = stored;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}
