/// Which response headers a baseline remembers, and the part of each value that is worth comparing.
///
/// Most headers (dates, request ids, cookies, server timing) differ on every response and say nothing about the
/// contract, so only a short list is kept: the kind of body, its encoding and language, caching, an API version,
/// and the headers whose appearance is itself news (a deprecation notice, rate limits).
abstract final class BaselineHeaders {
  /// Headers whose value (reduced by [_reduce]) is remembered.
  static const _valued = {
    'content-type',
    'content-encoding',
    'content-language',
    'cache-control',
    'x-api-version',
    'api-version',
  };

  /// Headers whose value changes all the time but whose presence matters.
  static const _presence = {
    'deprecation',
    'sunset',
    'retry-after',
    'x-ratelimit-limit',
    'x-ratelimit-remaining',
    'x-ratelimit-reset',
    'ratelimit-limit',
    'ratelimit-remaining',
    'ratelimit-reset',
  };

  static const contentType = 'content-type';
  static const present = 'present';

  /// The remembered form of [headers] (names in any case): lower-case name to reduced value.
  static Map<String, String> of(Map<String, String> headers) {
    final out = <String, String>{};
    final lower = {for (final e in headers.entries) e.key.toLowerCase(): e.value};
    for (final name in [..._valued, ..._presence]) {
      final value = lower[name];
      if (value == null) continue;
      out[name] = _presence.contains(name) ? present : _reduce(name, value);
    }
    return out;
  }

  static String _reduce(String name, String value) {
    final text = value.trim().toLowerCase();
    switch (name) {
      case 'content-type':
        // The media type: parameters such as the charset or a multipart boundary are not the contract.
        return text.split(';').first.trim();
      case 'cache-control':
        final directives = {
          for (final part in text.split(','))
            if (part.trim().isNotEmpty) part.split('=').first.trim(),
        }.toList()
          ..sort();
        return directives.join(',');
      default:
        return text;
    }
  }
}
