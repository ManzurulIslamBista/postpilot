import '../../../request_builder/domain/entities/api_response_entity.dart';

/// What one try of a request gave: a response, or no response at all (the network failed). A request that cannot
/// be built at all is not an exchange: that is an exception that ends the flow.
sealed class FlowExchange {
  const FlowExchange();
}

final class FlowResponded extends FlowExchange {
  final ApiResponseEntity response;
  const FlowResponded(this.response);
}

final class FlowFailed extends FlowExchange {
  /// The original failure, handed back to the caller unchanged when the flow ends with it.
  final Object error;

  /// One line saying what went wrong, safe to show and to write into a report.
  final String summary;
  const FlowFailed(this.error, this.summary);
}

/// Thrown by a send function when one try of a flow must not go out (the production lock refuses it, a variable is
/// missing). It ends the flow at once and is never retried.
final class FlowBlocked implements Exception {
  final String message;
  const FlowBlocked(this.message);

  @override
  String toString() => message;
}

/// One HTTP try of a flow, as shown in the console and in run results: `attempt 2/3 after 1.2 s`.
final class FlowAttempt {
  /// What this try was: `request`, `attempt 2/3 after 1.2 s`, `poll 3/30 after 2 s`, `page 4`.
  final String label;

  /// The status of the answer; null when the network failed.
  final int? status;

  /// What went wrong when there was no answer.
  final String? error;
  final Duration took;

  /// A repeat of a try that failed (a retry), as opposed to the first try of a request, a poll or a page.
  final bool isRetry;

  const FlowAttempt({required this.label, this.status, this.error, this.took = Duration.zero, this.isRetry = false});

  String get text => error != null ? '$label: $error' : '$label: HTTP $status';
}

/// Why fetching pages ended.
enum PaginationStop {
  /// The strategy said there is no next page: everything was fetched.
  lastPage('all pages fetched'),

  /// A page without items ended the walk.
  emptyPage('stopped at an empty page'),

  /// The page limit was reached while the server still had more.
  maxPages('stopped at the page limit; the server has more pages'),

  /// A page came back that was already fetched (a repeated cursor or URL, or the server ignoring the page
  /// parameter), so going on would never end.
  cycle('stopped because the server returned a page it had already sent'),

  /// The pages together grew past the size limit.
  sizeCap('stopped at the size limit; the server has more pages'),

  /// The next-page link points at another host, which is never followed (the credentials would go with it).
  crossOrigin('stopped because the next-page link points to another host'),

  /// A page could not be read as the strategy expects (not JSON, no items array).
  unreadable('stopped because a page could not be read'),

  /// A page failed; what was fetched until then is returned.
  failed('stopped because a page failed');

  final String text;
  const PaginationStop(this.text);

  /// Whether everything the server has was fetched.
  bool get complete => this == lastPage || this == emptyPage;
}

/// The outcome of a fetch-all-pages walk.
final class PageSummary {
  final int pages;
  final int items;
  final PaginationStop stop;

  /// More about the stop (which host, which page failed); null when [PaginationStop.text] says it.
  final String? detail;
  final String strategy;

  const PageSummary({
    required this.pages,
    required this.items,
    required this.stop,
    required this.strategy,
    this.detail,
  });

  /// `5 pages, 482 items`.
  String get badge => '$pages ${pages == 1 ? 'page' : 'pages'}, $items ${items == 1 ? 'item' : 'items'}';

  bool get complete => stop.complete;
}

/// What the flow around a send did, for the console, the response strip, run results and the command line.
final class FlowReport {
  /// Every HTTP try, in order.
  final List<FlowAttempt> attempts;

  /// Tries that were repeats of one that failed.
  final int retries;

  /// Times the request was sent while polling (the first send counts); 0 when it was not polled.
  final int polls;
  final bool pollSatisfied;
  final PageSummary? pages;

  /// Things worth knowing that did not fail the request ("not retried: POST ...", "stopped at the page limit").
  final List<String> notes;

  /// Why the flow ended unsuccessfully (a poll that never held, a page that failed); null otherwise. A failed
  /// request fails with this even when every response was a 200.
  final String? failure;

  const FlowReport({
    this.attempts = const [],
    this.retries = 0,
    this.polls = 0,
    this.pollSatisfied = false,
    this.pages,
    this.notes = const [],
    this.failure,
  });

  static const empty = FlowReport();

  /// More than a plain send happened, so the response strip has something to say.
  bool get isNoteworthy => retries > 0 || polls > 1 || pages != null || notes.isNotEmpty || failure != null;

  /// One line: `3 attempts · polled 5 times · 4 pages, 312 items`.
  String get summary {
    final parts = [
      if (retries > 0) '${retries + 1} attempts',
      if (polls > 1) 'polled $polls times',
      if (polls == 1 && pollSatisfied) 'condition held on the first try',
      if (pages case final summary?) summary.badge,
    ];
    return parts.join(' · ');
  }

  /// [summary] with the retries spelled out, for a line of text: `3 attempts: attempt 2/3 after 1.2 s, attempt 3/3 after
  /// 1.2 s · 4 pages, 312 items`.
  String get detailed {
    final labels = [for (final attempt in attempts) if (attempt.isRetry) attempt.label];
    final shown = labels.length > 3 ? [...labels.take(3), '…'] : labels;
    final parts = [
      if (retries > 0) '${retries + 1} attempts${shown.isEmpty ? '' : ': ${shown.join(', ')}'}',
      if (polls > 1) 'polled $polls times',
      if (pages case final summary?) summary.badge,
    ];
    return parts.join(' · ');
  }
}

/// What [FlowExecutor.execute] hands back.
final class FlowOutcome {
  /// The response to show: the last one, or the pages merged into one. Null when the network failed.
  final ApiResponseEntity? response;

  /// The failure when there is no [response]; the same object a plain send would have thrown.
  final Object? error;
  final FlowReport report;

  const FlowOutcome({this.response, this.error, this.report = FlowReport.empty});

  bool get failed => error != null || report.failure != null;
}
