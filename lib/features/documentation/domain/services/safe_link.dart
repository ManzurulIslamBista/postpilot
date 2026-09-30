/// Which links in user-written docs may be followed or exported as a link.
abstract final class SafeLink {
  static final _ignorable = RegExp(r'[\u0000- \u007F-\u009F]');

  /// True for web, mail and in-page links; `javascript:`, `data:`, `file:` and
  /// the like are refused, also when disguised with spaces or control characters.
  static bool isAllowed(String url) {
    final cleaned = url.replaceAll(_ignorable, '').toLowerCase();
    return cleaned.startsWith('http://') ||
        cleaned.startsWith('https://') ||
        cleaned.startsWith('mailto:') ||
        cleaned.startsWith('#');
  }
}
