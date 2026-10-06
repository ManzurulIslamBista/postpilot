import '../../../request_builder/domain/entities/api_response_entity.dart';

/// The last few responses of each request in this session, kept in memory only
/// (bodies are deliberately not stored in History). It is what "compare with
/// the previous response" reads.
///
/// Bodies can be large (the size limit in Settings defaults to 50 MB), so the
/// history is bounded twice: a few responses per request, and a total number of
/// bytes after which the oldest responses of any request are dropped.
final class ResponseHistory {
  static const _perRequest = 8;

  /// What is kept in total, by body size. The response just recorded always stays,
  /// even when it alone is larger.
  final int maxTotalBytes;

  ResponseHistory({this.maxTotalBytes = 64 * 1024 * 1024});

  final Map<int, List<ApiResponseEntity>> _byRequest = {};
  final Map<ApiResponseEntity, DateTime> _receivedAt = {};

  /// Which request a response belongs to, and when it was recorded relative to the others.
  final Map<ApiResponseEntity, int> _owner = {};
  final Map<ApiResponseEntity, int> _order = {};
  int _sequence = 0;
  int _totalBytes = 0;

  /// Bytes of body currently held.
  int get totalBytes => _totalBytes;

  /// Remembers [response] for [requestId], newest first. The same response
  /// twice (a widget rebuilt with an unchanged value) is stored once.
  void record(int requestId, ApiResponseEntity response, {DateTime? at}) {
    final list = _byRequest.putIfAbsent(requestId, () => []);
    if (list.any((r) => identical(r, response))) return;
    list.insert(0, response);
    _receivedAt[response] = at ?? DateTime.now();
    _owner[response] = requestId;
    _order[response] = ++_sequence;
    _totalBytes += response.sizeBytes;
    while (list.length > _perRequest) {
      _drop(list.removeLast());
    }
    _evictOldest(keep: response);
  }

  /// Newest first.
  List<ApiResponseEntity> of(int requestId) => List.unmodifiable(_byRequest[requestId] ?? const []);

  DateTime? receivedAt(ApiResponseEntity response) => _receivedAt[response];

  /// Drops everything remembered for [requestId] (its tab was closed, or it was deleted).
  void forget(int requestId) {
    for (final r in _byRequest.remove(requestId) ?? const <ApiResponseEntity>[]) {
      _drop(r);
    }
  }

  /// Forgets every request that is not in [requestIds]: the ones whose tabs are still open.
  void retainOnly(Iterable<int> requestIds) {
    final keep = requestIds.toSet();
    for (final id in _byRequest.keys.where((id) => !keep.contains(id)).toList()) {
      forget(id);
    }
  }

  void _drop(ApiResponseEntity response) {
    _receivedAt.remove(response);
    _owner.remove(response);
    _order.remove(response);
    _totalBytes -= response.sizeBytes;
  }

  void _evictOldest({required ApiResponseEntity keep}) {
    while (_totalBytes > maxTotalBytes) {
      ApiResponseEntity? oldest;
      for (final r in _order.keys) {
        if (identical(r, keep)) continue;
        if (oldest == null || _order[r]! < _order[oldest]!) oldest = r;
      }
      if (oldest == null) return;
      final owner = _owner[oldest]!;
      final list = _byRequest[owner]!..removeWhere((r) => identical(r, oldest));
      if (list.isEmpty) _byRequest.remove(owner);
      _drop(oldest);
    }
  }
}
