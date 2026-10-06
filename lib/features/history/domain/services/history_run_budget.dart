/// How many sends of one collection run reach History. A run can send
/// thousands of requests (iterations x requests); recorded in full they would
/// push everything the person sent by hand out of the list. The first
/// [okLimit] successful sends are kept as a sample, and failed ones (the ones
/// worth looking at) up to [limit] in all.
final class HistoryRunBudget {
  static const defaultLimit = 50;
  static const defaultOkLimit = 20;

  final int limit;
  final int okLimit;
  int _used = 0;
  int _okUsed = 0;

  HistoryRunBudget({this.limit = defaultLimit, this.okLimit = defaultOkLimit});

  /// How many sends this run has put in History so far.
  int get recorded => _used;

  /// Whether one more send of this run (a response with [statusCode], or no
  /// response at all when null) is recorded; asking uses up a slot when it is.
  bool admit({required int? statusCode}) {
    if (_used >= limit) return false;
    final ok = statusCode != null && statusCode >= 200 && statusCode < 300;
    if (ok && _okUsed >= okLimit) return false;
    _used++;
    if (ok) _okUsed++;
    return true;
  }
}
