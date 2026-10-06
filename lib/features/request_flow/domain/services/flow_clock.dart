import 'dart:async';
import '../../../../core/network/api_http_response.dart';

/// Time for the flow engine: what time it is, and waiting. Injectable so the backoff of a retry can be tested
/// without waiting for it.
abstract interface class FlowClock {
  DateTime now();

  /// Completes after [duration], or at once when [cancel] fires first.
  Future<void> sleep(Duration duration, {ApiCancelToken? cancel});
}

final class SystemFlowClock implements FlowClock {
  const SystemFlowClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> sleep(Duration duration, {ApiCancelToken? cancel}) {
    if (duration <= Duration.zero || (cancel?.isCancelled ?? false)) return Future.value();
    final done = Completer<void>();
    // A Timer that is cancelled with the wait, so nothing is left pending after a Stop.
    final timer = Timer(duration, () {
      if (!done.isCompleted) done.complete();
    });
    cancel?.whenCancelled.then((_) {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }
}
