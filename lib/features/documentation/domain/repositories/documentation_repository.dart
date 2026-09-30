import '../entities/entity_kind.dart';

abstract interface class DocumentationRepository {
  /// Empty when the entity has no description.
  Future<String> markdownOf(EntityKind kind, int id);

  /// An empty [text] removes the stored description.
  Future<void> setMarkdown(EntityKind kind, int id, String text);

  Future<Map<int, String>> markdownByLocalId(EntityKind kind);
}
