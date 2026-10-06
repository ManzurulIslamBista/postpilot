import 'history_entry_entity.dart';

/// How far back the History list reaches.
enum HistoryRange {
  today('Today'),
  week('Last 7 days'),
  all('All time');

  const HistoryRange(this.label);

  final String label;
}

/// What narrows the History list. Every part is optional; the parts are ANDed.
final class HistoryFilter {
  final String query;
  final HistoryStatusClass? statusClass;

  /// Upper-case method name.
  final String? method;
  final int? collectionId;
  final HistoryRange range;

  const HistoryFilter({
    this.query = '',
    this.statusClass,
    this.method,
    this.collectionId,
    this.range = HistoryRange.all,
  });

  /// Something other than the query narrows the list.
  bool get hasFacets => statusClass != null || method != null || collectionId != null || range != HistoryRange.all;

  bool get isActive => hasFacets || query.trim().isNotEmpty;

  HistoryFilter copyWith({
    String? query,
    Object? statusClass = _keep,
    Object? method = _keep,
    Object? collectionId = _keep,
    HistoryRange? range,
  }) =>
      HistoryFilter(
        query: query ?? this.query,
        statusClass: identical(statusClass, _keep) ? this.statusClass : statusClass as HistoryStatusClass?,
        method: identical(method, _keep) ? this.method : method as String?,
        collectionId: identical(collectionId, _keep) ? this.collectionId : collectionId as int?,
        range: range ?? this.range,
      );

  /// The facets of [entry] match; the query is matched separately (it also looks inside bodies).
  bool matchesFacets(HistoryEntryEntity entry, DateTime now) {
    final wanted = statusClass;
    if (wanted != null && entry.statusClass != wanted) return false;
    final wantedMethod = method;
    if (wantedMethod != null && entry.method.toUpperCase() != wantedMethod) return false;
    final wantedCollection = collectionId;
    if (wantedCollection != null && entry.meta?.collectionId != wantedCollection) return false;
    final local = entry.sentAt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    return switch (range) {
      HistoryRange.all => true,
      HistoryRange.today => !local.isBefore(today),
      // Calendar days, not 144 hours: a clock change must not move the edge.
      HistoryRange.week => !local.isBefore(DateTime(today.year, today.month, today.day - 6)),
    };
  }

  static const _keep = Object();
}
