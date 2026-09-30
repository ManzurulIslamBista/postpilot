import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../domain/entities/entity_kind.dart';
import '../../domain/repositories/tag_repository.dart';
import '../../domain/services/tag_matcher.dart';

/// The tag filter of the sidebar. Any number of tags can be selected and a
/// request shows when it matches one of them, through its own tags or those of
/// its folders and collection. It is a [ValueListenable] of the matching
/// request ids (null = no filter) so the sidebar can follow it without
/// knowing about tags.
final class TagFilterViewModel with ChangeNotifier implements ValueListenable<Set<int>?> {
  final TagRepository _tags;
  final CollectionRepository _collections;
  final RequestRepository _requests;

  TagFilterViewModel(this._tags, this._collections, this._requests) {
    _subscriptions.add(_tags.watchAllTags().listen(_onAllTags));
    for (final kind in EntityKind.values) {
      _subscriptions.add(_tags.watchTagsByLocalId(kind).listen((byId) {
        _tagsByKind[kind] = byId;
        _recompute();
      }));
    }
  }

  List<String> allTags = const [];

  final Set<String> _selected = {};
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Map<EntityKind, Map<int, List<String>>> _tagsByKind = {};
  StreamSubscription<List<CollectionEntity>>? _collectionsSubscription;
  final Map<int, StreamSubscription<Object?>> _folderSubscriptions = {};
  final Map<int, StreamSubscription<Object?>> _requestSubscriptions = {};
  final Map<int, List<FolderEntity>> _folders = {};
  final Map<int, List<RequestSummaryEntity>> _requestsByCollection = {};
  Set<int>? _matching;

  bool get isFiltering => _selected.isNotEmpty;

  bool isSelected(String tag) => _selected.contains(tag.trim().toLowerCase());

  Set<String> get selectedTags => {
        for (final tag in allTags)
          if (isSelected(tag)) tag,
      };

  /// Ids of the requests to show, or null when no tag is selected.
  Set<int>? get matchingRequestIds => _matching;

  @override
  Set<int>? get value => _matching;

  void toggleTag(String tag) {
    final key = tag.trim().toLowerCase();
    if (!_selected.remove(key)) _selected.add(key);
    _selectionChanged();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    _selectionChanged();
  }

  void _selectionChanged() {
    if (_selected.isEmpty) {
      _stopWatchingTree();
    } else {
      _collectionsSubscription ??= _collections.watchCollections().listen(_onCollections);
    }
    _matching = _compute();
    notifyListeners();
  }

  /// A tag nobody uses any more cannot stay selected: it would keep filtering
  /// with no chip left to switch it off.
  void _onAllTags(List<String> tags) {
    if (listEquals(tags, allTags)) return;
    allTags = tags;
    final known = {for (final tag in tags) tag.toLowerCase()};
    final before = _selected.length;
    _selected.retainAll(known);
    if (_selected.length == before) {
      notifyListeners();
    } else {
      _selectionChanged();
    }
  }

  void _onCollections(List<CollectionEntity> collections) {
    final ids = {for (final collection in collections) collection.id};
    for (final id in _folderSubscriptions.keys.where((id) => !ids.contains(id)).toList()) {
      _folderSubscriptions.remove(id)?.cancel();
      _requestSubscriptions.remove(id)?.cancel();
      _folders.remove(id);
      _requestsByCollection.remove(id);
    }
    for (final id in ids) {
      _folderSubscriptions.putIfAbsent(id, () => _collections.watchFolders(id).listen((folders) {
            _folders[id] = folders;
            _recompute();
          }));
      _requestSubscriptions.putIfAbsent(id, () => _requests.watchByCollection(id).listen((requests) {
            _requestsByCollection[id] = requests;
            _recompute();
          }));
    }
    _recompute();
  }

  void _stopWatchingTree() {
    _collectionsSubscription?.cancel();
    _collectionsSubscription = null;
    for (final subscription in [..._folderSubscriptions.values, ..._requestSubscriptions.values]) {
      subscription.cancel();
    }
    _folderSubscriptions.clear();
    _requestSubscriptions.clear();
    _folders.clear();
    _requestsByCollection.clear();
  }

  void _recompute() {
    final next = _compute();
    if (setEquals(next, _matching)) return;
    _matching = next;
    notifyListeners();
  }

  Set<int>? _compute() => _selected.isEmpty
      ? null
      : TagMatcher.matchingRequestIds(
          selected: _selected,
          requestTags: _tagsByKind[EntityKind.request] ?? const {},
          folderTags: _tagsByKind[EntityKind.folder] ?? const {},
          collectionTags: _tagsByKind[EntityKind.collection] ?? const {},
          foldersByCollection: _folders,
          requestsByCollection: _requestsByCollection,
        );

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _stopWatchingTree();
    super.dispose();
  }
}
