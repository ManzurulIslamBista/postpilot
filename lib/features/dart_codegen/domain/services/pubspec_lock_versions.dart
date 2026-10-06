import 'package:yaml/yaml.dart';

/// Reads the versions a project has already resolved out of its `pubspec.lock`, so the
/// generated dev-dependency lines name versions that project demonstrably uses.
abstract final class PubspecLockVersions {
  /// Package name to resolved version. Anything that is not a readable lock file gives an empty map.
  static Map<String, String> parse(String lockText) {
    if (lockText.trim().isEmpty) return const {};
    try {
      final document = loadYaml(lockText);
      if (document is! Map) return const {};
      final packages = document['packages'];
      if (packages is! Map) return const {};
      final versions = <String, String>{};
      packages.forEach((name, entry) {
        if (entry is Map && entry['version'] is String) versions['$name'] = entry['version'] as String;
      });
      return versions;
    } catch (_) {
      return const {};
    }
  }
}
