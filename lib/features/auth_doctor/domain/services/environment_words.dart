// Pure Dart (no Flutter, no database).
import '../../../safety/domain/services/production_detector.dart';

/// What a name or a host says about the kind of server: production, or a place to try things.
enum ServerKind { production, staging }

/// Tells production from staging by the words in an environment name or a host name. Production words are the app's own
/// (see [ProductionDetector]); a host is read the same way, one label at a time.
abstract final class EnvironmentWords {
  static const stagingWords = {
    'staging',
    'stage',
    'stg',
    'dev',
    'develop',
    'development',
    'test',
    'testing',
    'qa',
    'uat',
    'sandbox',
    'sbx',
    'preprod',
    'preproduction',
    'demo',
    'local',
    'localhost',
    'integration',
    'sit',
  };

  /// The kind [text] names, or null when it says neither. A text that says both (`prod-test`) is staging: the safe reading.
  static ServerKind? kindOf(String text) {
    final words = _words(text);
    if (words.any(stagingWords.contains)) return ServerKind.staging;
    if (ProductionDetector.isProduction(words.join(' '))) return ServerKind.production;
    return null;
  }

  /// The kind of a host: `api.staging.acme.com` is staging, `prod-api.acme.com` production, `api.acme.com` neither.
  static ServerKind? kindOfHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '127.0.0.1' || h == '::1' || h.endsWith('.localhost') || h.endsWith('.local')) return ServerKind.staging;
    // The registrable part (`acme.com`) is the company's name, not the kind of server.
    final labels = h.split('.');
    final own = labels.length > 2 ? labels.sublist(0, labels.length - 2) : (labels.length == 1 ? labels : <String>[]);
    return kindOf(own.join(' '));
  }

  static List<String> _words(String text) => text
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// `api.acme.com` and `login.acme.com` share `acme.com`.
  static String baseDomain(String host) {
    final labels = host.toLowerCase().split('.');
    if (labels.length <= 2) return labels.join('.');
    const secondLevel = {'co', 'com', 'org', 'net', 'gov', 'ac', 'edu'};
    final take = labels.last.length == 2 && secondLevel.contains(labels[labels.length - 2]) ? 3 : 2;
    return labels.sublist(labels.length - take).join('.');
  }
}
