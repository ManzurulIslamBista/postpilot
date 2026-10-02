import '../../../request_builder/domain/entities/api_response_entity.dart';

/// The last few responses of each request in this session, kept in memory only
/// (bodies are deliberately not stored in History). It is what "compare with
/// the previous response" reads.
final class ResponseHistory {
  static const _perRequest = 8;

  final Map<int, List<ApiResponseEntity>> _byRequest = {};
  final Map<ApiResponseEntity, DateTime> _receivedAt = {};

  /// Remembers [response] for [requestId], newest first. The same response
  /// twice (a widget rebuilt with an unchanged value) is stored once.
  void record(int requestId, ApiResponseEntity response, {DateTime? at}) {
    final list = _byRequest.putIfAbsent(requestId, () => []);
    if (list.any((r) => identical(r, response))) return;
    list.insert(0, response);
    _receivedAt[response] = at ?? DateTime.now();
    while (list.length > _perRequest) {
      _receivedAt.remove(list.removeLast());
    }
  }

  /// Newest first.
  List<ApiResponseEntity> of(int requestId) => List.unmodifiable(_byRequest[requestId] ?? const []);

  DateTime? receivedAt(ApiResponseEntity response) => _receivedAt[response];

  void forget(int requestId) {
    for (final r in _byRequest.remove(requestId) ?? const <ApiResponseEntity>[]) {
      _receivedAt.remove(r);
    }
  }
}
