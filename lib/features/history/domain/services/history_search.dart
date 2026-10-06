import '../entities/history_entry_entity.dart';

/// What the History search box matches against.
abstract final class HistorySearch {
  /// How much of a request body and of a response body is searchable. The rest of a body is still shown, just not found.
  static const requestExcerptChars = 1000;
  static const responseExcerptChars = 4000;

  /// The text stored in `history_payloads.search_text`: method, URL, request
  /// name, collection, environment, status, and an excerpt of each body, lower-cased
  /// the way a query is. It is built from the already masked texts, so a search can
  /// never find a secret that was hidden.
  static String searchText({
    required String method,
    required String url,
    String? requestName,
    String? collectionName,
    String? environmentName,
    int? statusCode,
    String? statusMessage,
    String? requestBody,
    String? responseBody,
    String? error,
  }) {
    String excerpt(String? text, int chars) => text == null ? '' : (text.length <= chars ? text : text.substring(0, chars));
    return [
      method,
      url,
      requestName ?? '',
      collectionName ?? '',
      environmentName ?? '',
      statusCode?.toString() ?? '',
      statusMessage ?? '',
      error ?? '',
      excerpt(requestBody, requestExcerptChars),
      excerpt(responseBody, responseExcerptChars),
    ].where((part) => part.isNotEmpty).join(' ').toLowerCase();
  }

  /// A query as the database wants it: trimmed and lower-cased; empty when there is nothing to search for.
  static String normalise(String query) => query.trim().toLowerCase();

  /// Whether the summary of [entry] (what is on screen in its row) matches the lower-cased [needle].
  /// Entries that kept no details are found by this alone; the rest are found by their stored text too.
  static bool matchesSummary(HistoryEntryEntity entry, String needle) {
    if (needle.isEmpty) return true;
    final meta = entry.meta;
    final fields = [
      entry.method,
      entry.url,
      entry.statusCode?.toString(),
      meta?.statusMessage,
      meta?.requestName,
      meta?.collectionName,
      meta?.environmentName,
    ];
    return fields.any((field) => field != null && field.toLowerCase().contains(needle));
  }
}
