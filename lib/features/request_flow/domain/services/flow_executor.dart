import 'dart:math' as math;
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../scripting/domain/entities/assertion_result.dart';
import '../../../scripting/domain/evaluator/assertion_evaluator.dart';
import '../entities/flow_report.dart';
import '../entities/flow_settings.dart';
import '../entities/pagination_settings.dart';
import 'flow_clock.dart';
import 'odoo_count.dart';
import 'page_requests.dart';
import 'pagination_engine.dart';
import 'retry_planner.dart';

/// Sends one try of a request and says what came of it: a response, or a [FlowFailed] when the network failed.
/// Anything else it throws ends the flow (a request that cannot be built is no reason to try again).
typedef FlowSend = Future<FlowExchange> Function(ApiRequestEntity request);

/// Told what the flow is doing, in a few words (`attempt 2/3 after 1.2 s`, `poll 4/30 after 2 s`, `page 3`).
typedef FlowNote = void Function(String message);

/// What the flow needs from the app around it.
final class FlowContext {
  /// The variables as they are now: a poll condition or a Run if may name a value an earlier request just saved.
  final Future<VariableResolver> Function() resolver;
  final FlowNote? onNote;
  final ApiCancelToken? cancelToken;

  const FlowContext({required this.resolver, this.onNote, this.cancelToken});
}

/// Sends a request the way its flow settings say: retrying when the network or the server fails, repeating until
/// a condition holds (poll), and fetching every page of a list into one response. The three nest in this order:
/// a retry wraps each single HTTP try; a poll repeats the request, each repetition retried on its own; fetching
/// pages comes last, from the response the retry and the poll ended with. Pure Dart over a [FlowSend] function, so
/// the app, the collection runner and the command line all run the same engine.
final class FlowExecutor {
  final FlowClock clock;
  final double Function() _random;

  FlowExecutor({this.clock = const SystemFlowClock(), double Function()? random})
      : _random = random ?? math.Random().nextDouble;

  /// Whether anything in these settings changes how the request is sent (Run if and Always run only matter in a run).
  static bool changesSending(FlowSettings flow, PaginationSettings pagination) =>
      flow.retry.enabled || flow.poll.isActive || pagination.enabled;

  Future<FlowOutcome> execute({
    required ApiRequestEntity request,
    required FlowSettings flow,
    required PaginationSettings pagination,
    required FlowSend send,
    required FlowContext context,
  }) =>
      _FlowRun(this, request, flow, pagination, send, context).execute();
}

final class _FlowRun {
  final FlowExecutor _executor;
  final ApiRequestEntity _request;
  final FlowSettings _flow;
  final PaginationSettings _pagination;
  final FlowSend _send;
  final FlowContext _context;

  final List<FlowAttempt> _attempts = [];
  final List<String> _notes = [];
  final List<String> _authNotes = [];
  int _retries = 0;
  int _polls = 0;
  bool _pollSatisfied = false;
  PageSummary? _pages;
  String? _failure;

  late bool _retryOn = _flow.retry.enabled;
  late bool _pollOn = _flow.poll.isActive;
  late bool _pagesOn = _pagination.enabled;

  _FlowRun(this._executor, this._request, this._flow, this._pagination, this._send, this._context);

  FlowClock get _clock => _executor.clock;

  Future<FlowOutcome> execute() async {
    final blocked = RepeatSafety.blockedReason(_request.method, _flow);
    if (blocked != null && (_retryOn || _pollOn || _pagesOn)) {
      _notes.add('Retry, poll and fetch-all-pages are off for this send: $blocked');
      _retryOn = _pollOn = _pagesOn = false;
    }
    if (_flow.poll.enabled && _flow.poll.until.isEmpty) {
      _notes.add('Poll until is on but has no condition, so the request was sent once.');
    }

    final started = _clock.now();
    var exchange = await _exchange(_request, 'request');
    if (_pollOn) exchange = await _poll(exchange, started);
    if (exchange is! FlowResponded) return _outcome(null, (exchange as FlowFailed).error);

    var response = exchange.response;
    if (_pagesOn && _failure == null) response = await _paginate(response) ?? response;
    return _outcome(response, null);
  }

  FlowOutcome _outcome(ApiResponseEntity? response, Object? error) {
    // What the app did about authentication on any try (a token renewed, a re-login) belongs to the answer shown.
    final shown = response?.withAuthNotes([
      for (final note in _authNotes)
        if (!response.authNotes.contains(note)) note,
    ]);
    return FlowOutcome(
      response: shown,
      error: error,
      report: FlowReport(
        attempts: _attempts,
        retries: _retries,
        polls: _polls,
        pollSatisfied: _pollSatisfied,
        pages: _pages,
        notes: _notes,
        failure: _failure,
      ),
    );
  }

  // --- one exchange, retried -----------------------------------------------------------------------------------

  /// Sends [request], and again while the retry policy says so. [base] says what it is for (`request`, `poll 3/30
  /// after 2 s`, `page 4`) and prefixes the label of every try.
  Future<FlowExchange> _exchange(ApiRequestEntity request, String base) async {
    final policy = _flow.retry;
    final planner = _retryOn ? RetryPlanner(policy, _executor._random) : null;
    final attempts = _retryOn ? 1 + policy.maxRetries : 1;
    final started = _clock.now();
    var attempt = 1;
    Duration? waited;
    while (true) {
      _checkCancelled();
      final label = _label(base, attempt, attempts, waited);
      if (label != 'request') _context.onNote?.call(label);
      final exchange = await _send(request);
      if (exchange is FlowResponded) {
        for (final note in exchange.response.authNotes) {
          if (!_authNotes.contains(note)) _authNotes.add(note);
        }
      }
      _attempts.add(FlowAttempt(
        label: label,
        status: exchange is FlowResponded ? exchange.response.statusCode : null,
        error: exchange is FlowFailed ? exchange.summary : null,
        took: exchange is FlowResponded ? exchange.response.duration : Duration.zero,
        isRetry: attempt > 1,
      ));
      if (planner == null) return exchange;
      final decision = planner.decide(
        attempt: attempt,
        exchange: exchange,
        elapsed: _clock.now().difference(started),
        now: _clock.now(),
      );
      switch (decision) {
        case RetryStop(:final note):
          if (note != null) _notes.add(note);
          return exchange;
        case RetryWait(:final wait):
          await _clock.sleep(wait, cancel: _context.cancelToken);
          _checkCancelled();
          waited = wait;
          attempt++;
          _retries++;
      }
    }
  }

  static String _label(String base, int attempt, int attempts, Duration? waited) {
    if (attempt == 1) return base;
    final retry = 'attempt $attempt/$attempts after ${_seconds(waited!)}';
    return base == 'request' ? retry : '$base, $retry';
  }

  // --- poll ---------------------------------------------------------------------------------------------------

  Future<FlowExchange> _poll(FlowExchange first, DateTime started) async {
    final policy = _flow.poll;
    final interval = Duration(milliseconds: policy.intervalMs);
    final limit = Duration(seconds: policy.maxSeconds);
    var exchange = first;
    _polls = 1;
    while (true) {
      if (exchange is! FlowResponded) return exchange;
      final results = await _evaluate(exchange.response);
      if (results.every((r) => r.passed)) {
        _pollSatisfied = true;
        return exchange;
      }
      final elapsed = _clock.now().difference(started);
      if (_polls >= policy.maxAttempts || elapsed + interval > limit) {
        _failure = _pollTimeout(results, elapsed);
        return exchange;
      }
      await _clock.sleep(interval, cancel: _context.cancelToken);
      _checkCancelled();
      _polls++;
      exchange = await _exchange(_request, 'poll $_polls/${policy.maxAttempts} after ${_seconds(interval)}');
    }
  }

  Future<List<AssertionResult>> _evaluate(ApiResponseEntity response) async =>
      const AssertionEvaluator().evaluate(response, _flow.poll.until, await _context.resolver());

  String _pollTimeout(List<AssertionResult> results, Duration elapsed) {
    final policy = _flow.poll;
    final waiting = [
      for (final r in results)
        if (!r.passed) '${SecretMasker.maskMessage(r.name)} (got ${_shown(r)})',
    ];
    return 'Polling gave up after $_polls ${_polls == 1 ? 'request' : 'requests'} in ${_seconds(elapsed)} '
        '(the limits are ${policy.maxAttempts} requests and ${policy.maxSeconds} s). '
        'Still waiting for: ${waiting.join('; ')}. The last response is shown.';
  }

  /// What a condition saw, masked: it is a piece of the response and may hold a credential.
  static String _shown(AssertionResult result) => SecretMasker.isSensitiveName(result.name)
      ? SecretMasker.mask
      : SecretMasker.maskMessage(SecretMasker.maskBody(result.actual));

  // --- fetch all pages -----------------------------------------------------------------------------------------

  /// The first response with the items of every page merged into it; null when the walk could not start (the
  /// response then stays as it is, and [_failure] or a note says why).
  Future<ApiResponseEntity?> _paginate(ApiResponseEntity first) async {
    final settings = _pagination;
    final problem = settings.problem;
    if (problem != null) {
      _failure = 'Fetch all pages is on but not set up: $problem.';
      return null;
    }
    if (!first.isSuccess) {
      _notes.add('Fetch all pages was skipped: the first response is HTTP ${first.statusCode}.');
      return null;
    }
    final decoded = PageItems.decode(first);
    if (!decoded.valid) {
      _failure = 'Fetch all pages needs a JSON response, and this one is not JSON.';
      return null;
    }
    final firstItems = PageItems.at(decoded.value, settings.itemsPath);
    if (firstItems == null) {
      _failure = 'There is no array at ${_where(settings.itemsPath)} in the first response, so its pages cannot be '
          'merged. Change the items path in the Flow tab.';
      return null;
    }

    final resolver = await _context.resolver();
    final items = <Object?>[...firstItems];
    var page = FetchedPage(request: _request, response: first, json: decoded.value, itemCount: firstItems.length);
    var lastItems = firstItems;
    var pages = 1;
    var bytes = first.bodyBytes.length;
    var duration = first.duration;
    var truncated = first.truncated;
    final sizeLimit = settings.maxMegabytes * 1024 * 1024;
    final seen = <String>{};
    PaginationStop stop;
    String? detail;
    final total = settings.countTotal && settings.kind == PaginationKind.offset ? await _countRecords(resolver) : null;
    // With the count known the pages can be numbered "2/7".
    final pageSize = _pageSize(settings, resolver, firstItems.length);
    final expectedPages = total != null && pageSize > 0 ? (total / pageSize).ceil() : null;

    while (true) {
      final next = PaginationEngine.next(settings, page, resolver, total: total);
      if (next is NoNextPage) {
        stop = next.stop;
        detail = next.detail;
        break;
      }
      next as NextPageRequest;
      if (pages >= settings.maxPages) {
        stop = PaginationStop.maxPages;
        break;
      }
      if (!seen.add(next.key)) {
        stop = PaginationStop.cycle;
        detail = 'It sent the same next-page link or token twice.';
        break;
      }
      _checkCancelled();
      if (settings.delayMs > 0) {
        await _clock.sleep(Duration(milliseconds: settings.delayMs), cancel: _context.cancelToken);
        _checkCancelled();
      }
      final number = pages + 1;
      final exchange = await _exchange(next.request, expectedPages == null ? 'page $number' : 'page $number/$expectedPages');
      if (exchange is! FlowResponded) {
        stop = PaginationStop.failed;
        detail = 'Page $number failed: ${(exchange as FlowFailed).summary}';
        break;
      }
      final response = exchange.response;
      if (!response.isSuccess) {
        stop = PaginationStop.failed;
        final message = response.statusMessage.isEmpty ? '' : ' ${response.statusMessage}';
        detail = 'Page $number failed: HTTP ${response.statusCode}$message';
        break;
      }
      final body = PageItems.decode(response);
      final pageItems = body.valid ? PageItems.at(body.value, settings.itemsPath) : null;
      if (pageItems == null) {
        stop = PaginationStop.unreadable;
        detail = 'Page $number has no array at ${_where(settings.itemsPath)}.';
        break;
      }
      if (pageItems.isEmpty && settings.stopOnEmpty) {
        stop = PaginationStop.emptyPage;
        break;
      }
      if (PageItems.same(pageItems, lastItems)) {
        stop = PaginationStop.cycle;
        detail = 'Page $number has the same items as page ${number - 1}: the server seems to ignore the page parameter.';
        break;
      }
      bytes += response.bodyBytes.length;
      if (bytes > sizeLimit) {
        stop = PaginationStop.sizeCap;
        detail = 'The pages together passed ${settings.maxMegabytes} MB.';
        break;
      }
      items.addAll(pageItems);
      lastItems = pageItems;
      pages++;
      duration += response.duration;
      truncated = truncated || response.truncated;
      page = FetchedPage(request: next.request, response: response, json: body.value, itemCount: pageItems.length);
    }

    _pages = PageSummary(pages: pages, items: items.length, stop: stop, strategy: settings.kind.label, detail: detail);
    if (stop == PaginationStop.failed) {
      _failure = '${detail!.replaceAll(RegExp(r'\.+$'), '')}. The result holds what was fetched until then: ${_pages!.badge}.';
    } else if (!stop.complete) {
      _notes.add('${_capital(stop.text)}${detail == null ? '' : ': $detail'}');
    }
    return PaginationEngine.merge(
      first: first,
      itemsPath: settings.itemsPath,
      items: items,
      duration: duration,
      truncated: truncated,
    );
  }

  /// How many records there are in all, from an Odoo `search_count` of the same model and domain; null when it cannot
  /// be asked or answered (a note says so), and the walk then ends at a page that comes back short or empty.
  Future<int?> _countRecords(VariableResolver resolver) async {
    final count = OdooCount.requestFor(_request, resolver);
    if (count == null) {
      _notes.add('"Count the records first" is only for an Odoo JSON-2 search_read, so the pages are fetched until one '
          'comes back short or empty.');
      return null;
    }
    final exchange = await _exchange(count, 'search_count');
    if (exchange is FlowResponded && exchange.response.isSuccess) {
      final value = PageItems.decode(exchange.response).value;
      if (value is num && value.isFinite && value >= 0) return value.toInt();
    }
    _notes.add('The record count could not be read, so the pages are fetched until one comes back short or empty.');
    return null;
  }

  /// How many items a full page holds: the limit the request sets, else what the first page held.
  int _pageSize(PaginationSettings settings, VariableResolver resolver, int firstPageItems) {
    if (settings.limitParam.isNotEmpty) {
      final limit = int.tryParse(PageRequests.read(_request, settings.limitParam, settings.location, resolver) ?? '');
      if (limit != null && limit > 0) return limit;
    }
    return firstPageItems;
  }

  static String _where(String path) => path.isEmpty ? 'the top level of the body' : '"$path"';

  static String _capital(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

  void _checkCancelled() {
    if (_context.cancelToken?.isCancelled ?? false) {
      throw const NetworkException('Request cancelled', kind: NetworkErrorKind.cancelled);
    }
  }

  /// `1.2 s`, `30 s`, `500 ms`.
  static String _seconds(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms < 1000) return '$ms ms';
    final seconds = ms / 1000;
    return '${seconds == seconds.truncateToDouble() ? seconds.toInt() : seconds.toStringAsFixed(1)} s';
  }
}
