import '../entities/recorded_exchange.dart';

/// The calls the recorder keeps in memory: a ring buffer with two limits, a number of calls and a number of bytes, so a long
/// session cannot grow without bound. When either is exceeded the oldest calls are dropped.
final class RecordingBuffer {
  final int maxCount;
  final int maxBytes;
  final _items = <RecordedExchange>[];
  var _bytes = 0;
  var _dropped = 0;

  RecordingBuffer({this.maxCount = 1000, this.maxBytes = 64 * 1024 * 1024})
      : assert(maxCount > 0),
        assert(maxBytes > 0);

  /// Oldest first.
  List<RecordedExchange> get items => List.unmodifiable(_items);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  /// What the kept calls weigh, roughly.
  int get bytes => _bytes;

  /// How many calls were dropped to stay within the limits since the last [clear].
  int get dropped => _dropped;

  void add(RecordedExchange exchange) {
    _items.add(exchange);
    _bytes += exchange.approximateBytes;
    // The newest call always stays, even when it alone is over the byte limit.
    while (_items.length > 1 && (_items.length > maxCount || _bytes > maxBytes)) {
      _bytes -= _items.removeAt(0).approximateBytes;
      _dropped++;
    }
  }

  RecordedExchange? byId(int id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  void clear() {
    _items.clear();
    _bytes = 0;
    _dropped = 0;
  }
}
