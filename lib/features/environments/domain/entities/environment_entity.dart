final class EnvironmentEntity {
  final int id;
  final String name;
  final bool isActive;

  const EnvironmentEntity({required this.id, required this.name, required this.isActive});
}

final class EnvironmentVariableEntity {
  final int id;
  final int environmentId;
  final String key;
  final String value;
  final bool isSecret;
  final bool enabled;

  const EnvironmentVariableEntity({
    required this.id,
    required this.environmentId,
    required this.key,
    required this.value,
    required this.isSecret,
    required this.enabled,
  });
}
