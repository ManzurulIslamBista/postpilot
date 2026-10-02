import '../../../../core/enums/http_method.dart';

/// Decides which environments count as "production" and which requests change
/// data. Detection is by name, because that is how people label environments:
/// "Production", "Prod (EU)", "live", "acme-prod".
abstract final class ProductionDetector {
  static const builtInWords = {'prod', 'production', 'prd', 'live'};

  /// True when any word of [environmentName] is a production word, built in or in [extraWords].
  static bool isProduction(String environmentName, {Iterable<String> extraWords = const []}) {
    final words = environmentName
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    final wanted = {...builtInWords, for (final w in extraWords) if (w.trim().isNotEmpty) w.trim().toLowerCase()};
    return words.any(wanted.contains);
  }

  /// Methods that change data on the server.
  static bool changesData(HttpMethod method) =>
      method == HttpMethod.post || method == HttpMethod.put || method == HttpMethod.patch || method == HttpMethod.delete;
}
