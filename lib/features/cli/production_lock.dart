// Pure Dart (no Flutter), like the rest of the command line.
import '../safety/domain/services/production_detector.dart';

/// The production lock of the command line and the MCP server: a request that
/// would change data is refused while the environment (or the host) looks like
/// production, unless the person who started the process said `--allow-production`.
/// An agent cannot lift it: the flag is read once at start-up and no tool
/// argument touches it.
final class ProductionLock {
  /// `--allow-production`: send data-changing requests to production anyway.
  final bool allow;

  /// `--production-word`: names that mean production on top of `prod`, `production`, `prd` and `live`.
  final List<String> extraWords;

  /// `--production-host`: hosts that are production whatever the environment is called
  /// (`api.acme.com`, `*.acme.com`, `acme.com:8443`).
  final List<String> hosts;

  const ProductionLock({this.allow = false, this.extraWords = const [], this.hosts = const []});

  /// Whether [environment] looks like production.
  bool isProductionEnvironment(String environment) => ProductionDetector.isProduction(environment, extraWords: extraWords);

  /// Why a request to [url] under [environment] counts as production; `null` when it does not.
  String? reason(String? environment, String url) {
    if (environment != null && isProductionEnvironment(environment)) {
      return 'environment "$environment" looks like production';
    }
    if (ProductionDetector.isProductionHost(url, hosts)) return '${ProductionDetector.hostOf(url)} is a production host';
    return null;
  }
}

/// One request the lock refuses.
final class ProductionBlock {
  final String collection;
  final String folder;
  final String name;
  final String method;
  final RequestEffect effect;
  final String reason;

  const ProductionBlock({
    required this.collection,
    required this.folder,
    required this.name,
    required this.method,
    required this.effect,
    required this.reason,
  });

  String get label => [collection, if (folder.isNotEmpty) folder, name].join(' / ');

  /// A refused request on one line: `DELETE Shop / Orders / Delete order (deletes data): environment "Production" ...`.
  String get line => '${method.padRight(6)} $label${effect == RequestEffect.destructive ? ' (deletes data)' : ''}: $reason';

  /// The message that says which requests were refused and how to allow them.
  static String describe(List<ProductionBlock> blocks, {required String howToAllow}) {
    final count = blocks.length;
    final b = StringBuffer('Production lock: $count selected request${count == 1 ? '' : 's'} would change data in production, so nothing was sent.');
    for (final block in blocks) {
      b.write('\n  ${block.line}');
    }
    b.write('\n$howToAllow');
    return b.toString();
  }
}
