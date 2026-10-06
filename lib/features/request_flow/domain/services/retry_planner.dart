import '../../../../core/enums/http_method.dart';
import '../entities/flow_report.dart';
import '../entities/flow_settings.dart';

/// Whether a request may be sent again without changing anything twice. GET, HEAD, OPTIONS and PUT can; POST,
/// PATCH and DELETE might create, change or remove something each time, so they are only repeated when the
/// person said so ([FlowSettings.repeatUnsafe]).
abstract final class RepeatSafety {
  static bool needsConfirmation(HttpMethod method) =>
      method == HttpMethod.post || method == HttpMethod.patch || method == HttpMethod.delete;

  /// Why [method] is not repeated under [flow], or null when it may be.
  static String? blockedReason(HttpMethod method, FlowSettings flow) => needsConfirmation(method) && !flow.repeatUnsafe
      ? '${method.label} may change data each time it is sent, so it is not repeated. '
          'Tick "I know repeating this request is safe" in the Flow tab to allow it.'
      : null;
}

/// The `Retry-After` header: a number of seconds, or an HTTP date.
abstract final class RetryAfter {
  static final _seconds = RegExp(r'^\d{1,9}$');
  static final _date = RegExp(r'^[A-Za-z]{3}, (\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$');
  static const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

  /// How long to wait as of [now]; null when [header] is missing or cannot be read. A date in the past is no wait.
  static Duration? parse(String? header, DateTime now) {
    final text = header?.trim();
    if (text == null || text.isEmpty) return null;
    if (_seconds.hasMatch(text)) return Duration(seconds: int.parse(text));
    final match = _date.firstMatch(text);
    if (match == null) return null;
    final month = _months.indexOf(match[2]!.toLowerCase());
    if (month < 0) return null;
    final date = DateTime.utc(
      int.parse(match[3]!),
      month + 1,
      int.parse(match[1]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
    final wait = date.difference(now.toUtc());
    return wait.isNegative ? Duration.zero : wait;
  }
}

sealed class RetryDecision {
  const RetryDecision();
}

/// Send again after [wait].
final class RetryWait extends RetryDecision {
  final Duration wait;
  const RetryWait(this.wait);
}

/// Do not send again. [note] says why when a retry was wanted but refused (the attempts or the time ran out).
final class RetryStop extends RetryDecision {
  final String? note;
  const RetryStop([this.note]);
}

/// Decides, after each try, whether to try again and how long to wait first.
final class RetryPlanner {
  final RetryPolicy policy;

  /// A number in [0, 1), for the jitter; injectable for tests.
  final double Function() random;

  const RetryPlanner(this.policy, this.random);

  /// The wait before retry number [retryNumber] (1 for the first retry) as planned: [RetryPolicy.delayMs], doubled
  /// for each retry after the first when exponential, never above [RetryPolicy.maxDelayMs]; with jitter a random
  /// 50-100% of that. [randomValue] is the jitter draw in [0, 1).
  static Duration plannedWait(RetryPolicy policy, int retryNumber, {double randomValue = 1}) {
    var ms = policy.delayMs;
    if (policy.backoff == BackoffKind.exponential) {
      // Stops doubling at the ceiling so a long series cannot overflow.
      for (var i = 1; i < retryNumber && ms < policy.maxDelayMs; i++) {
        ms *= 2;
      }
      if (ms > policy.maxDelayMs) ms = policy.maxDelayMs;
    }
    if (policy.jitter) ms = (ms * (0.5 + 0.5 * randomValue)).round();
    return Duration(milliseconds: ms);
  }

  /// [attempt] (1-based) is the try that just ended with [exchange], [elapsed] the time since the first try began.
  RetryDecision decide({
    required int attempt,
    required FlowExchange exchange,
    required Duration elapsed,
    required DateTime now,
  }) {
    final retryable = switch (exchange) {
      FlowFailed() => policy.onNetworkError,
      FlowResponded(:final response) => policy.retriesStatus(response.statusCode),
    };
    if (!retryable) return const RetryStop();
    final attempts = 1 + policy.maxRetries;
    if (attempt >= attempts) return RetryStop('gave up after $attempt attempts');

    Duration? asked;
    if (exchange is FlowResponded && policy.honourRetryAfter) {
      asked = RetryAfter.parse(_header(exchange, 'retry-after'), now);
    }
    final wait = asked ?? plannedWait(policy, attempt, randomValue: random());
    final limit = Duration(seconds: policy.maxTotalSeconds);
    if (elapsed + wait > limit) {
      return RetryStop(
        asked == null
            ? 'gave up after $attempt ${attempt == 1 ? 'attempt' : 'attempts'}: the next wait would pass the '
                '${policy.maxTotalSeconds} s time limit'
            : 'gave up: the server asked to wait ${_seconds(asked)} (Retry-After), which is past the '
                '${policy.maxTotalSeconds} s time limit',
      );
    }
    return RetryWait(wait);
  }

  static String? _header(FlowResponded exchange, String name) {
    for (final entry in exchange.response.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  static String _seconds(Duration duration) => '${(duration.inMilliseconds / 1000).round()} s';
}
