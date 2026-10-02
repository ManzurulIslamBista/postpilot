import 'dart:convert';
import '../../../documentation/domain/services/secret_masker.dart';

/// A Markdown write-up of one request/response, safe to paste into an issue or
/// a pull request: every credential in the URL, headers and bodies is masked
/// first by the same [SecretMasker] the API docs use.
abstract final class BugReportBuilder {
  static String build({
    required String method,
    required String url,
    Map<String, String> requestHeaders = const {},
    String? requestBody,
    required int statusCode,
    String statusText = '',
    int? durationMs,
    int? sizeBytes,
    Map<String, String> responseHeaders = const {},
    String? responseBody,
    String? note,
    int maxBodyChars = 4000,
  }) {
    final b = StringBuffer()..writeln('## API issue');
    if (note != null && note.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln(note.trim());
    }
    b
      ..writeln()
      ..writeln('### Request')
      ..writeln()
      ..writeln('```http')
      ..writeln('$method ${SecretMasker.maskUrl(url)}');
    requestHeaders.forEach((k, v) => b.writeln('$k: ${SecretMasker.maskValue(k, v)}'));
    b.writeln('```');
    if (requestBody != null && requestBody.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('```${_lang(requestBody)}')
        ..writeln(_clip(SecretMasker.maskBody(_pretty(requestBody)), maxBodyChars))
        ..writeln('```');
    }
    b
      ..writeln()
      ..writeln('### Response')
      ..writeln()
      ..writeln(
        '**$statusCode ${statusText.trim()}**'
        '${durationMs == null ? '' : ' · $durationMs ms'}'
        '${sizeBytes == null ? '' : ' · ${_size(sizeBytes)}'}',
      )
      ..writeln();
    if (responseHeaders.isNotEmpty) {
      b.writeln('```http');
      responseHeaders.forEach((k, v) => b.writeln('$k: ${SecretMasker.maskValue(k, v)}'));
      b.writeln('```');
      b.writeln();
    }
    if (responseBody != null && responseBody.trim().isNotEmpty) {
      b
        ..writeln('```${_lang(responseBody)}')
        ..writeln(_clip(SecretMasker.maskBody(_pretty(responseBody)), maxBodyChars))
        ..writeln('```');
    }
    b
      ..writeln()
      ..writeln('<sub>Secrets masked by PostPilot.</sub>');
    return b.toString();
  }

  static String _pretty(String text) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } catch (_) {
      return text;
    }
  }

  static String _lang(String text) {
    final t = text.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) return 'json';
    if (t.startsWith('<')) return 'xml';
    return '';
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}\n… (${s.length - max} more characters)';

  static String _size(int bytes) => bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';
}
