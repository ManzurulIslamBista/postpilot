import '../../../history/domain/services/har_exporter.dart';
import '../../../mock_server/domain/services/mock_log.dart';
import '../entities/recorded_exchange.dart';
import 'traffic_masking.dart';

/// A recorded call as a cURL command.
abstract final class RecordingCurl {
  /// The command that repeats [e] against the upstream, credentials masked unless [reveal]. A body that was cut or is not
  /// text is not included, and the first line says so.
  static String build(RecordedExchange e, {bool reveal = false}) {
    final headers = <String, String>{};
    for (final h in TrafficMasking.headers(e.requestHeaders, reveal: reveal, dropTransport: true)) {
      final key = headers.keys.firstWhere((k) => k.toLowerCase() == h.name.toLowerCase(), orElse: () => h.name);
      final separator = key.toLowerCase() == 'cookie' ? '; ' : ', ';
      headers[key] = headers.containsKey(key) ? '${headers[key]}$separator${h.value}' : h.value;
    }
    final text = e.requestText;
    final complete = e.hasRequestBody && text != null && !e.requestBodyTruncated;
    final command = MockCurl.build(
      method: e.method,
      url: TrafficMasking.url(e.url, reveal: reveal),
      headers: headers,
      body: complete ? TrafficMasking.body(text, reveal: reveal) : '',
    );
    if (!e.hasRequestBody || complete) return command;
    final why = e.requestBodyTruncated ? 'was cut at the recorder\'s size limit' : 'is not text';
    return '# The request body $why, so it is not part of this command.\n$command';
  }
}

/// Recorded calls as a HAR 1.2 file, through the same exporter History uses (which masks credentials again).
abstract final class RecordingHar {
  static List<HarEntryInput> inputs(List<RecordedExchange> exchanges) => [
        for (final e in exchanges)
          HarEntryInput(
            startedAt: e.startedAt,
            durationMs: e.duration.inMilliseconds,
            method: e.method,
            url: e.url,
            requestHeaders: [
              for (final h in e.requestHeaders)
                if (!TrafficMasking.transportHeaders.contains(h.name.toLowerCase())) HarHeader(h.name, h.value),
            ],
            requestMimeType: e.requestContentType?.split(';').first.trim(),
            requestBody: e.requestText,
            statusCode: e.status,
            statusText: e.statusMessage,
            responseHeaders: [for (final h in e.responseHeaders) HarHeader(h.name, h.value)],
            responseMimeType: e.responseContentType?.split(';').first.trim(),
            responseText: e.responseText,
            // HAR's content.size is the decoded size; a cut body only knows how much came over the wire.
            responseBytes: e.responseBodyTruncated ? e.responseBodySize : e.responseBody.length,
            responseTruncated: e.responseBodyTruncated,
            error: e.error,
          ),
      ];

  static String export(List<RecordedExchange> exchanges) => HarExporter.export(inputs(exchanges));
}
