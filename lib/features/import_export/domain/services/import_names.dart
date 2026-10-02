/// Cleans names that arrive from a foreign file before they are stored.
abstract final class ImportNames {
  static final _lineBreak = RegExp(r'[\r\n\u0085  ]');
  static final _lineBreaks = RegExp(r'\s*[\r\n\u0085  ]+\s*');

  /// A folder is shown (and exported, e.g. as a comment banner in a cURL
  /// script) as one line, so a line break in an imported name becomes a single
  /// space. A name without one is returned as it is.
  static String folder(String name) {
    if (!name.contains(_lineBreak)) return name;
    final collapsed = name.replaceAll(_lineBreaks, ' ').trim();
    return collapsed.isEmpty ? 'Folder' : collapsed;
  }
}
