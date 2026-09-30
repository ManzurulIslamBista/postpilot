import '../entities/entity_kind.dart';

/// Tags are case-insensitive identities that keep the spelling they were
/// first given; reads return them sorted case-insensitively.
abstract interface class TagRepository {
  Stream<List<String>> watchTags(EntityKind kind, int id);

  /// Replaces the entity's tags; blanks and case-insensitive duplicates are dropped.
  Future<void> setTags(EntityKind kind, int id, List<String> tags);

  /// Every tag in use, one spelling per tag.
  Stream<List<String>> watchAllTags();

  Future<Map<int, List<String>>> tagsByLocalId(EntityKind kind);

  /// Re-emits whenever any tag of [kind] entities changes, so a caller can
  /// keep a live copy of everyone's tags.
  Stream<Map<int, List<String>>> watchTagsByLocalId(EntityKind kind);
}
