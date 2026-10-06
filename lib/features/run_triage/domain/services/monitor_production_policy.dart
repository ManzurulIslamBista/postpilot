import '../../../../core/enums/body_type.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../safety/domain/services/production_detector.dart';

/// A request the monitor will not send, and why.
final class MonitorSkip {
  final ApiRequestEntity request;
  final String reason;
  const MonitorSkip(this.request, this.reason);
}

/// What the monitor sends and what it leaves out.
final class MonitorPlan {
  final List<ApiRequestEntity> allowed;
  final List<MonitorSkip> skipped;
  const MonitorPlan(this.allowed, this.skipped);
}

/// The production lock of the monitor. A person confirms a data-changing request to production in the runner; nobody is
/// there to confirm a monitor's, so it never sends one: whatever changes data (judged by what the request does, not by
/// its verb: an Odoo `search_read` or a GraphQL query over POST is a read) is left out and listed in the run record.
/// There is no switch for it.
abstract final class MonitorProductionPolicy {
  /// [requests] are the requests of the run with their addresses resolved the way a send resolves them.
  /// [productionEnvironment] is true when the run's environment looks like production; [productionHosts] are the hosts
  /// of Settings > Safety, which are production under any environment name.
  static MonitorPlan plan(
    List<({ApiRequestEntity request, String resolvedUrl})> requests, {
    required bool productionEnvironment,
    Iterable<String> productionHosts = const [],
  }) {
    final allowed = <ApiRequestEntity>[];
    final skipped = <MonitorSkip>[];
    for (final (:request, :resolvedUrl) in requests) {
      final effect = ProductionDetector.classify(
        request.method,
        url: resolvedUrl,
        body: request.body.type == BodyType.raw ? request.body.rawText : null,
        graphqlQuery: request.body.type == BodyType.graphql ? request.body.graphqlQuery : null,
      );
      if (!effect.changesData) {
        allowed.add(request);
        continue;
      }
      final hostIsProduction = ProductionDetector.isProductionHost(resolvedUrl, productionHosts);
      if (!productionEnvironment && !hostIsProduction) {
        allowed.add(request);
        continue;
      }
      final where = productionEnvironment
          ? 'the environment looks like production'
          : '${ProductionDetector.hostOf(resolvedUrl)} is one of your production hosts';
      skipped.add(MonitorSkip(request, 'Left out by the monitor: it ${effect == RequestEffect.destructive ? 'deletes' : 'changes'} data and $where. '
          'The monitor never sends data-changing requests to production.'));
    }
    return MonitorPlan(allowed, skipped);
  }
}
