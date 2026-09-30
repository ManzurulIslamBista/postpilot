final class GlobalVariableEntity {
  final int id;
  final String key;
  final String value;
  final bool isSecret;
  final bool enabled;

  const GlobalVariableEntity({
    required this.id,
    required this.key,
    required this.value,
    required this.isSecret,
    required this.enabled,
  });
}
