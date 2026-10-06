/// Which web origins the mock server lets read its answers. `*` is everyone;
/// otherwise a list of origins (`http://localhost:5173`).
abstract final class MockCors {
  static const any = '*';

  /// The origins in [text] (`*`, or origins separated by commas or spaces), each
  /// lower-cased and without a trailing slash; null when something in it is not an
  /// origin. Blank text means [any].
  static List<String>? parse(String text) {
    final parts = text.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return const [any];
    final origins = <String>[];
    for (final part in parts) {
      final origin = normalize(part);
      if (origin == null) return null;
      if (origin == any) return const [any];
      if (!origins.contains(origin)) origins.add(origin);
    }
    return origins;
  }

  /// `HTTP://Localhost:5173/` becomes `http://localhost:5173`; null for text that is not a
  /// bare origin (a path, a query, no scheme).
  static String? normalize(String origin) {
    final t = origin.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
    if (t == any) return any;
    return RegExp(r'^[a-z][a-z0-9+.-]*://[^/\s?#@]+$').hasMatch(t) ? t : null;
  }

  /// Whether an `Origin` header sent by a browser is one of [allowed].
  static bool allows(List<String> allowed, String? requestOrigin) {
    if (allowed.contains(any)) return true;
    if (requestOrigin == null) return false;
    final origin = normalize(requestOrigin);
    return origin != null && allowed.contains(origin);
  }
}
