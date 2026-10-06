/// Which family of HTTP statuses an entry falls in, for the History filter.
/// [failed] is a send that got no response at all (DNS, refused, timeout).
enum HistoryStatusClass {
  success('2xx'),
  redirect('3xx'),
  clientError('4xx'),
  serverError('5xx'),
  failed('No response');

  const HistoryStatusClass(this.label);

  final String label;

  /// The class of [statusCode]; null for a code outside 2xx-5xx (an informational 1xx is never a final answer).
  static HistoryStatusClass? of(int? statusCode) {
    if (statusCode == null) return failed;
    if (statusCode >= 500 && statusCode < 600) return serverError;
    if (statusCode >= 400) return clientError;
    if (statusCode >= 300) return redirect;
    if (statusCode >= 200) return success;
    return null;
  }
}

/// What History knows about an entry beyond its one-line summary: where the
/// request came from and a few facts about the answer. It comes from the
/// request snapshot stored beside the entry, so it is absent for entries
/// recorded before History kept details or while "Keep request/response
/// bodies in history" was off.
final class HistoryEntryMeta {
  /// The saved request that was sent; it may have been deleted since.
  final int? requestId;
  final String? requestName;
  final int? collectionId;
  final String? collectionName;
  final String? environmentName;

  /// The size of the response body as it arrived, not as much of it as is kept.
  final int? responseBytes;
  final bool responseTruncated;

  /// The stored response has a text body to show.
  final bool hasResponseBody;
  final String? statusMessage;

  /// Why there is no response (one masked line), for a send that failed.
  final String? error;

  const HistoryEntryMeta({
    this.requestId,
    this.requestName,
    this.collectionId,
    this.collectionName,
    this.environmentName,
    this.responseBytes,
    this.responseTruncated = false,
    this.hasResponseBody = false,
    this.statusMessage,
    this.error,
  });
}

final class HistoryEntryEntity {
  final int id;
  final String method;
  final String url;
  final int? statusCode;
  final int? durationMs;
  final DateTime sentAt;

  /// Null when only the summary was kept (see [HistoryEntryMeta]).
  final HistoryEntryMeta? meta;

  const HistoryEntryEntity({
    required this.id,
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
    required this.sentAt,
    this.meta,
  });

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;

  /// The send produced no response.
  bool get isFailure => statusCode == null;

  HistoryStatusClass? get statusClass => HistoryStatusClass.of(statusCode);

  /// A request snapshot is stored with this entry, so it can be shown, edited and sent again as it was.
  bool get hasDetails => meta != null;
}
