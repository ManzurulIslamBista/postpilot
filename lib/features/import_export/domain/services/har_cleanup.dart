// Pure Dart (no Flutter, no database): runs in an isolate for a big recording.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import '../../../../core/enums/http_method.dart';
import '../../../traffic_recorder/domain/entities/recorded_exchange.dart';
import '../../../traffic_recorder/domain/services/noise_filter.dart';
import '../../../traffic_recorder/domain/services/path_normalizer.dart';
import '../../../traffic_recorder/domain/services/recording_collection_builder.dart';
import 'har_parser.dart';

/// What "Clean up" makes of a HAR file: the same clean collection the traffic recorder builds from the calls of an app
/// (see [RecordingCollectionBuilder]), plus the count of what was left out and why.
///
/// A browser's recording is mostly not the API: fonts, scripts, images, analytics and trackers, CORS preflights, calls to
/// other hosts. The calls that remain are turned into [RecordedExchange]s, the recorder's own type, so everything the
/// recorder does applies as it is: static files, analytics hosts and preflights are dropped ([NoiseFilter]), ids in
/// paths become `{{variables}}` ([PathNormalizer]), repeated calls become one request with the others as saved examples,
/// requests are grouped into folders by their first path segment, and every credential becomes a secret variable instead of
/// a value ([RecordingCollectionBuilder] with its masking). Of repeated calls the most complete one is the request.
final class HarCleanup {
  /// What would be created.
  final RecordingPlan plan;

  /// `https://app.shop.test`: the origin with most calls, which becomes `{{baseUrl}}`.
  final String baseUrl;
  final String host;

  /// Entries in the file.
  final int entries;

  /// Entries that are not an http(s) call at all (a `data:` URL, a WebSocket).
  final int unreadable;

  /// Calls that got no answer (blocked, cancelled, failed in the browser).
  final int unanswered;

  /// Calls left out as noise, by why. Includes what the browser itself labels a font, a stylesheet or a script.
  final Map<NoiseReason, int> dropped;

  /// Calls to other hosts than [host], by host: not part of this collection.
  final Map<String, int> otherHosts;

  const HarCleanup({
    required this.plan,
    required this.baseUrl,
    required this.host,
    required this.entries,
    required this.unreadable,
    required this.unanswered,
    required this.dropped,
    required this.otherHosts,
  });

  int get droppedTotal => dropped.values.fold(0, (a, b) => a + b);
  int get otherHostCalls => otherHosts.values.fold(0, (a, b) => a + b);

  /// Every entry that did not become part of a request.
  int get skipped => unreadable + unanswered + droppedTotal + otherHostCalls;

  /// The collection name of a plain HAR import (`HAR import - shop.test`).
  static String nameFor(String host) => host.isEmpty ? 'HAR import' : 'HAR import - $host';

  /// One sentence per thing that was left out or changed, for the import dialog; the plan's own notes are not in here.
  List<String> get notes {
    String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final reasons = <String>[
      if (dropped[NoiseReason.staticAsset] case final n?) plural(n, 'static file', 'static files'),
      if (dropped[NoiseReason.analytics] case final n?) plural(n, 'analytics or tracker call', 'analytics or tracker calls'),
      if (dropped[NoiseReason.preflight] case final n?) plural(n, 'CORS preflight', 'CORS preflights'),
      if (dropped[NoiseReason.unsupportedMethod] case final n?) plural(n, 'call with a method PostPilot cannot send', 'calls with a method PostPilot cannot send'),
      if (dropped[NoiseReason.notForwarded] case final n?) plural(n, 'call that was never made', 'calls that were never made'),
    ];
    final hosts = otherHosts.keys.take(4).join(', ');
    return [
      if (reasons.isNotEmpty) 'Left out ${plural(droppedTotal, 'call', 'calls')} that are not calls of the app\'s API: ${reasons.join(', ')}.',
      if (unanswered > 0) '${plural(unanswered, 'call', 'calls')} got no answer in the browser (blocked, cancelled or failed) and ${unanswered == 1 ? 'was' : 'were'} left out.',
      if (unreadable > 0) '${plural(unreadable, 'entry', 'entries')} ${unreadable == 1 ? 'was' : 'were'} not an http(s) call (a data: URL, a WebSocket) and ${unreadable == 1 ? 'was' : 'were'} left out.',
      if (otherHostCalls > 0)
        '${plural(otherHostCalls, 'call', 'calls')} to other hosts ($hosts${otherHosts.length > 4 ? ', ...' : ''}) ${otherHostCalls == 1 ? 'was' : 'were'} left out: '
            'this collection works against $baseUrl, the host with most calls, which is {{baseUrl}}.',
      if (plan.counts.merged > 0)
        'Repeated calls became one request each: ${plural(plan.counts.merged, 'call was', 'calls were')} merged. The most complete call of each is the request, '
            'the others are saved as examples, and ids in the path became variables.',
      if (plan.counts.examples > 0) '${plural(plan.counts.examples, 'response', 'responses')} saved as examples, with credentials in them masked.',
    ];
  }

  /// The most body PostPilot keeps of one call; more is cut, as the recorder cuts it.
  static const maxBodyBytes = 1024 * 1024;

  /// Cleans up the HAR file [text]. Throws what [HarParser.entriesOf] throws for a text that is no HAR file.
  static HarCleanup build(String text) {
    final raw = HarParser.entriesOf(text);
    var unreadable = 0;
    var unanswered = 0;
    final dropped = <NoiseReason, int>{};
    void drop(NoiseReason reason) => dropped.update(reason, (n) => n + 1, ifAbsent: () => 1);

    final calls = <RecordedExchange>[];
    for (final (index, entry) in raw.indexed) {
      final call = entry is Map ? _exchangeOf(entry, index) : null;
      if (call == null) {
        unreadable++;
        continue;
      }
      if (call.status <= 0) {
        unanswered++;
        continue;
      }
      final labelled = _noiseByLabel(entry as Map, call);
      if (labelled != null) {
        drop(labelled);
        continue;
      }
      calls.add(call);
    }

    // The host with most calls of the app's own is the API; the noise filter decides what is the app's own.
    final counts = <String, int>{};
    for (final call in calls) {
      if (!_isNoise(call)) counts.update(_originOf(call.url), (n) => n + 1, ifAbsent: () => 1);
    }
    final base = counts.isEmpty
        ? (calls.isEmpty ? '' : _originOf(calls.first.url))
        : counts.entries.reduce((best, e) => e.value > best.value ? e : best).key;

    final otherHosts = <String, int>{};
    final kept = <RecordedExchange>[];
    for (final call in calls) {
      if (_isNoise(call) || _originOf(call.url) == base) {
        kept.add(call);
      } else {
        otherHosts.update(Uri.parse(call.url).authority, (n) => n + 1, ifAbsent: () => 1);
      }
    }

    final host = base.isEmpty ? '' : Uri.parse(base).host;
    final ordered = _mostCompleteFirst(kept);
    final plan = RecordingCollectionBuilder.build(
      ordered,
      baseUrl: base,
      options: RecordingOptions(collectionName: nameFor(host)),
    );
    for (final entry in plan.counts.skipped.entries) {
      dropped.update(entry.key, (n) => n + entry.value, ifAbsent: () => entry.value);
    }
    return HarCleanup(
      plan: plan,
      baseUrl: base,
      host: host,
      entries: raw.length,
      unreadable: unreadable,
      unanswered: unanswered,
      dropped: dropped,
      otherHosts: otherHosts,
    );
  }

  // --- what the browser says a call is -------------------------------------------------------------------------

  /// Chrome writes what each entry is (`_resourceType`); Firefox and Safari do not, and then the type of the answer says it.
  static const _staticTypes = {'stylesheet', 'image', 'media', 'font', 'script', 'texttrack', 'manifest', 'prefetch'};
  static const _beaconTypes = {'ping', 'cspviolationreport'};
  static final _staticMime = RegExp(
    r'^(?:image/|font/|audio/|video/|text/css|(?:text|application)/(?:x-)?javascript|application/wasm|application/(?:x-)?font|application/vnd\.ms-fontobject)',
    caseSensitive: false,
  );

  static NoiseReason? _noiseByLabel(Map entry, RecordedExchange call) {
    final type = entry['_resourceType'];
    if (type is String && type.isNotEmpty) {
      final lower = type.toLowerCase();
      if (_staticTypes.contains(lower)) return NoiseReason.staticAsset;
      if (_beaconTypes.contains(lower)) return NoiseReason.analytics;
      if (lower == 'preflight') return NoiseReason.preflight;
      return null;
    }
    final mime = (call.responseContentType ?? '').trim();
    return _staticMime.hasMatch(mime) ? NoiseReason.staticAsset : null;
  }

  static bool _isNoise(RecordedExchange call) =>
      NoiseFilter.reasonFor(call) != null || !HttpMethod.values.any((m) => m.label == call.method);

  static String _originOf(String url) {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  // --- repeated calls: the most complete one first ----------------------------------------------------------------

  /// The calls grouped as the builder groups them (method and path with ids made variables), in the order each group first
  /// appears, the most complete call of a group leading it, so it is the request and the others its examples.
  static List<RecordedExchange> _mostCompleteFirst(List<RecordedExchange> calls) {
    final groups = <String, List<RecordedExchange>>{};
    final noise = <RecordedExchange>[];
    for (final call in calls) {
      if (_isNoise(call)) {
        noise.add(call);
        continue;
      }
      final question = call.path.indexOf('?');
      final pathOnly = question == -1 ? call.path : call.path.substring(0, question);
      groups.putIfAbsent('${call.method} ${PathNormalizer.normalize(pathOnly).template}', () => []).add(call);
    }
    final ordered = <RecordedExchange>[];
    for (final members in groups.values) {
      var best = members.first;
      for (final call in members.skip(1)) {
        if (_completeness(call) > _completeness(best)) best = call;
      }
      ordered.add(best);
      ordered.addAll(members.where((m) => !identical(m, best)));
    }
    ordered.addAll(noise);
    // The builder orders by time: the order decided here is given as the time.
    return [for (final (index, call) in ordered.indexed) _restamped(call, index)];
  }

  /// How much a call shows of what the request can be: it worked, it has a body, headers and a query, and the server answered with something.
  static int _completeness(RecordedExchange call) {
    var score = 0;
    if (call.succeeded) score += 1000;
    if (call.hasRequestBody) score += 300;
    score += math.min(call.requestHeaders.length, 40) * 2;
    score += (Uri.tryParse(call.url)?.queryParametersAll.length ?? 0) * 5;
    if (call.hasResponseBody) score += 100 + math.min(call.responseBodySize ~/ 1000, 50);
    return score;
  }

  static RecordedExchange _restamped(RecordedExchange e, int order) => RecordedExchange(
        id: order,
        startedAt: DateTime.utc(2000).add(Duration(milliseconds: order)),
        duration: e.duration,
        method: e.method,
        url: e.url,
        path: e.path,
        status: e.status,
        statusMessage: e.statusMessage,
        kind: e.kind,
        requestHeaders: e.requestHeaders,
        requestBody: e.requestBody,
        requestBodySize: e.requestBodySize,
        requestBodyTruncated: e.requestBodyTruncated,
        responseHeaders: e.responseHeaders,
        responseBody: e.responseBody,
        responseBodySize: e.responseBodySize,
        responseBodyTruncated: e.responseBodyTruncated,
        responseEncoding: e.responseEncoding,
        responseUndecoded: e.responseUndecoded,
        error: e.error,
      );

  // --- a HAR entry as a recorded call -------------------------------------------------------------------------------

  /// The entry as the recorder's type, or null when it is not an http(s) call. The `Host` header and the HTTP/2 pseudo-headers
  /// are left out: the recorder's own copy of them says where the recorder is, and the URL already says where the server is.
  static RecordedExchange? _exchangeOf(Map entry, int index) {
    final request = entry['request'];
    if (request is! Map) return null;
    final url = request['url'];
    final method = '${request['method'] ?? ''}'.toUpperCase();
    if (url is! String || method.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) return null;

    final requestHeaders = _headersOf(request['headers'], dropHost: true);
    if (!requestHeaders.any((h) => h.name.toLowerCase() == 'cookie') && request['cookies'] is List) {
      final cookies = [
        for (final c in request['cookies'] as List)
          if (c is Map && c['name'] is String) '${c['name']}=${c['value'] ?? ''}',
      ];
      if (cookies.isNotEmpty) requestHeaders.add(RecordedHeader('Cookie', cookies.join('; ')));
    }
    final post = request['postData'];
    var requestBytes = Uint8List(0);
    var requestSize = 0;
    var requestCut = false;
    if (post is Map) {
      final mime = '${post['mimeType'] ?? ''}'.trim();
      if (mime.isNotEmpty && !requestHeaders.any((h) => h.name.toLowerCase() == 'content-type')) {
        requestHeaders.add(RecordedHeader('Content-Type', mime));
      }
      final bytes = utf8.encode(_postText(post));
      requestSize = bytes.length;
      requestCut = bytes.length > maxBodyBytes;
      requestBytes = Uint8List.fromList(requestCut ? bytes.sublist(0, maxBodyBytes) : bytes);
    }

    final response = entry['response'];
    var status = 0;
    var statusText = '';
    var responseHeaders = <RecordedHeader>[];
    var responseBytes = Uint8List(0);
    var responseSize = 0;
    var responseCut = false;
    if (response is Map) {
      final code = response['status'];
      status = code is num ? code.toInt() : 0;
      statusText = '${response['statusText'] ?? ''}';
      responseHeaders = _headersOf(response['headers']);
      final content = response['content'];
      if (content is Map) {
        final mime = '${content['mimeType'] ?? ''}'.split(';').first.trim();
        if (mime.isNotEmpty && !responseHeaders.any((h) => h.name.toLowerCase() == 'content-type')) {
          responseHeaders.add(RecordedHeader('Content-Type', '${content['mimeType']}'));
        }
        final bytes = _contentBytes(content);
        responseSize = bytes.length;
        responseCut = bytes.length > maxBodyBytes;
        responseBytes = Uint8List.fromList(responseCut ? bytes.sublist(0, maxBodyBytes) : bytes);
      }
    }

    final time = entry['time'];
    return RecordedExchange(
      id: index,
      startedAt: DateTime.tryParse('${entry['startedDateTime'] ?? ''}')?.toUtc() ?? DateTime.utc(1970).add(Duration(milliseconds: index)),
      duration: Duration(milliseconds: time is num && time > 0 ? time.round() : 0),
      method: method,
      url: url,
      path: '${uri.path.isEmpty ? '/' : uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
      status: status,
      statusMessage: statusText,
      requestHeaders: requestHeaders,
      requestBody: requestBytes,
      requestBodySize: requestSize,
      requestBodyTruncated: requestCut,
      responseHeaders: responseHeaders,
      responseBody: responseBytes,
      responseBodySize: responseSize,
      responseBodyTruncated: responseCut,
    );
  }

  static List<RecordedHeader> _headersOf(Object? raw, {bool dropHost = false}) => [
        if (raw is List)
          for (final h in raw)
            if (h is Map && h['name'] is String && (h['name'] as String).trim().isNotEmpty)
              if (!(h['name'] as String).startsWith(':') && !(dropHost && (h['name'] as String).trim().toLowerCase() == 'host'))
                RecordedHeader((h['name'] as String).trim(), '${h['value'] ?? ''}'),
      ];

  /// The body of a request as text: what the file holds, else the form fields it lists.
  static String _postText(Map post) {
    final text = post['text'];
    if (text is String && text.isNotEmpty) return text;
    final params = post['params'];
    if (params is! List) return '';
    final pairs = [
      for (final p in params)
        if (p is Map && p['name'] is String && (p['name'] as String).isNotEmpty)
          '${Uri.encodeQueryComponent(p['name'] as String)}=${Uri.encodeQueryComponent('${p['value'] ?? ''}')}',
    ];
    return pairs.join('&');
  }

  /// The body of an answer: Chrome writes a binary one as base64.
  static List<int> _contentBytes(Map content) {
    final text = content['text'];
    if (text is! String || text.isEmpty) return const [];
    if (content['encoding'] == 'base64') {
      try {
        return base64.decode(base64.normalize(text));
      } on FormatException {
        return const [];
      }
    }
    return utf8.encode(text);
  }
}
