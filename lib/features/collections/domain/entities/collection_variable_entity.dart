final class CollectionVariableEntity {
  final int id;
  final int collectionId;
  final String key;
  final String value;
  final bool enabled;

  const CollectionVariableEntity({
    required this.id,
    required this.collectionId,
    required this.key,
    required this.value,
    required this.enabled,
  });
}
