/// A whole collection rendered as text, with what the rendering left out.
final class CollectionExportResult {
  final String collectionName;
  final String text;

  /// Requests written to [text].
  final int itemCount;

  /// Requests that could not be written (no URL, duplicate method+path, a
  /// request the command generator rejected).
  final int skipped;

  const CollectionExportResult({
    required this.collectionName,
    required this.text,
    required this.itemCount,
    required this.skipped,
  });
}
