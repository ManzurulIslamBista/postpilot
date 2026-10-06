import 'dart:convert';
import 'dart:typed_data';
import '../../../../core/utils/variable_resolver.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../entities/flow_report.dart';
import '../entities/pagination_settings.dart';
import 'json_path_editor.dart';
import 'page_requests.dart';

/// A response body as JSON: [valid] says whether it parsed (a JSON `null` body is valid and null).
typedef DecodedBody = ({bool valid, Object? value});

/// Reads the pages of a list.
abstract final class PageItems {
  static DecodedBody decode(ApiResponseEntity response) {
    try {
      return (valid: true, value: jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)));
    } on FormatException {
      return (valid: false, value: null);
    }
  }

  /// The array at [path] (the whole document when [path] is empty), null when it is not there or not an array.
  static List<Object?>? at(Object? document, String path) {
    final found = JsonPathEditor.read(document, path);
    return found is List ? found.cast<Object?>() : null;
  }

  /// Whether two pages hold the same items: a server that ignores the page parameter answers every request alike.
  static bool same(List<Object?> a, List<Object?> b) => a.isNotEmpty && jsonEncode(a) == jsonEncode(b);
}

/// The `Link` header of RFC 8288: `<https://api/x?page=2>; rel="next", <...>; rel="last"`.
abstract final class LinkHeader {
  static final _link = RegExp(r'<([^>]*)>((?:[^,<"]|"[^"]*")*)');
  static final _rel = RegExp(r'''rel\s*=\s*(?:"([^"]*)"|([^\s;,]+))''', caseSensitive: false);

  /// The target of the link whose relation includes `next`; null when there is none.
  static String? next(String? header) {
    if (header == null) return null;
    for (final match in _link.allMatches(header)) {
      final rel = _rel.firstMatch(match[2] ?? '');
      final relations = (rel?[1] ?? rel?[2] ?? '').toLowerCase().split(RegExp(r'\s+'));
      if (relations.contains('next')) return match[1]!.trim();
    }
    return null;
  }
}

/// The page just fetched, decoded once, with the request that fetched it.
final class FetchedPage {
  final ApiRequestEntity request;
  final ApiResponseEntity response;
  final Object? json;
  final int itemCount;

  const FetchedPage({required this.request, required this.response, required this.json, required this.itemCount});

  String? header(String name) {
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }
}

sealed class NextPage {
  const NextPage();
}

/// The request for the following page. [key] identifies where it points, to notice a server that sends the same
/// page twice.
final class NextPageRequest extends NextPage {
  final ApiRequestEntity request;
  final String key;
  const NextPageRequest(this.request, this.key);
}

final class NoNextPage extends NextPage {
  final PaginationStop stop;
  final String? detail;
  const NoNextPage(this.stop, [this.detail]);
}

/// Works out the request for the next page from the page just received, for each [PaginationKind]. Pure: it
/// sends nothing and keeps no state, so the same function serves the app, the runner and the command line.
abstract final class PaginationEngine {
  /// [total] is the number of records when it is known from outside the page (an Odoo `search_count`); a total in the
  /// page itself, at `totalPath`, wins over it.
  static NextPage next(PaginationSettings settings, FetchedPage page, VariableResolver resolver, {int? total}) {
    if (_hasMoreEnded(settings, page)) return const NoNextPage(PaginationStop.lastPage);
    return switch (settings.kind) {
      PaginationKind.linkHeader => _byUrl(LinkHeader.next(page.header('link')), page, resolver),
      PaginationKind.nextUrl => _nextUrl(settings, page, resolver),
      PaginationKind.cursor => _cursor(settings, page, resolver),
      PaginationKind.page => _pageNumber(settings, page, resolver),
      PaginationKind.offset => _offset(settings, page, resolver, total),
    };
  }

  /// The `hasMorePath` field says "no more": a boolean false (or the text or number that stands for it).
  static bool _hasMoreEnded(PaginationSettings settings, FetchedPage page) {
    if (settings.hasMorePath.isEmpty) return false;
    final value = _at(page.json, settings.hasMorePath);
    return value == false || value == 'false' || value == 0;
  }

  static NextPage _nextUrl(PaginationSettings settings, FetchedPage page, VariableResolver resolver) {
    final value = _at(page.json, settings.nextPath);
    if (value == null || (value is String && value.trim().isEmpty)) return const NoNextPage(PaginationStop.lastPage);
    if (value is! String) {
      return NoNextPage(PaginationStop.unreadable, '"${settings.nextPath}" is not a URL in this page.');
    }
    return _byUrl(value, page, resolver);
  }

  /// Follows [raw] (absolute, or relative to the page's own URL) when it stays on the same host.
  static NextPage _byUrl(String? raw, FetchedPage page, VariableResolver resolver) {
    final link = raw?.trim();
    if (link == null || link.isEmpty) return const NoNextPage(PaginationStop.lastPage);
    if (PageRequests.looksLikeVariable(link)) {
      return const NoNextPage(PaginationStop.unreadable, 'The next-page link contains "{{" and was not followed.');
    }
    final current = Uri.tryParse(_absolute(resolver.resolve(page.request.url)));
    final target = current == null ? null : _tryResolve(current, link);
    if (current == null || target == null || target.host.isEmpty) {
      return const NoNextPage(PaginationStop.unreadable, 'The next-page link is not a URL that can be followed.');
    }
    if (!PageRequests.sameOrigin(current, target)) {
      return NoNextPage(
        PaginationStop.crossOrigin,
        'The next-page link points to ${target.host}, not ${current.host}, so it was not followed.',
      );
    }
    return NextPageRequest(PageRequests.withUrl(page.request, target), 'url:$target');
  }

  static NextPage _cursor(PaginationSettings settings, FetchedPage page, VariableResolver resolver) {
    final token = _at(page.json, settings.nextPath);
    if (token == null || (token is String && token.isEmpty)) return const NoNextPage(PaginationStop.lastPage);
    if (token is! String && token is! num) {
      return NoNextPage(PaginationStop.unreadable, '"${settings.nextPath}" is not a token in this page.');
    }
    if (PageRequests.looksLikeVariable('$token')) {
      return const NoNextPage(PaginationStop.unreadable, 'The next-page token contains "{{" and was not used.');
    }
    return _write(settings, page, resolver, token, 'cursor:$token');
  }

  static NextPage _pageNumber(PaginationSettings settings, FetchedPage page, VariableResolver resolver) {
    final current = int.tryParse(PageRequests.read(page.request, settings.param, settings.location, resolver) ?? '');
    final number = current ?? settings.firstPage;
    final total = _int(_at(page.json, settings.totalPath));
    if (total != null && number >= settings.firstPage + total - 1) return const NoNextPage(PaginationStop.lastPage);
    return _write(settings, page, resolver, number + 1, 'page:${number + 1}');
  }

  static NextPage _offset(PaginationSettings settings, FetchedPage page, VariableResolver resolver, int? knownTotal) {
    final offset = int.tryParse(PageRequests.read(page.request, settings.param, settings.location, resolver) ?? '') ?? 0;
    final limit = settings.limitParam.isEmpty
        ? null
        : int.tryParse(PageRequests.read(page.request, settings.limitParam, settings.location, resolver) ?? '');
    final step = limit ?? page.itemCount;
    if (step <= 0) return const NoNextPage(PaginationStop.emptyPage);
    // A page shorter than the limit is the last one: the server had no more to fill it with.
    if (limit != null && page.itemCount < limit) return const NoNextPage(PaginationStop.lastPage);
    final total = _int(_at(page.json, settings.totalPath)) ?? knownTotal;
    final next = offset + step;
    if (total != null && next >= total) return const NoNextPage(PaginationStop.lastPage);
    return _write(settings, page, resolver, next, 'offset:$next');
  }

  static NextPage _write(PaginationSettings settings, FetchedPage page, VariableResolver resolver, Object value, String key) {
    try {
      return NextPageRequest(PageRequests.write(page.request, settings.param, settings.location, value, resolver), key);
    } on FormatException catch (e) {
      return NoNextPage(PaginationStop.unreadable, e.message);
    }
  }

  /// The value at [path]; null for an empty path, which the resolver would read as "the whole document".
  static Object? _at(Object? document, String path) => path.trim().isEmpty ? null : JsonPathEditor.read(document, path);

  static int? _int(Object? value) => switch (value) {
        int() => value,
        num() when value.isFinite => value.toInt(),
        String() => int.tryParse(value.trim()),
        _ => null,
      };

  static Uri? _tryResolve(Uri base, String link) {
    try {
      return base.resolve(link);
    } on FormatException {
      return null;
    }
  }

  /// The URL with the scheme the request builder would give it (`http://` when none is written).
  static String _absolute(String url) {
    final text = url.trim();
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text) ? text : 'http://$text';
  }

  /// [first]'s response with the items of every page in [pages] put together under [itemsPath], everything else
  /// as the first page had it. The pages' bodies are read as JSON again here, so [first] is not touched.
  static ApiResponseEntity merge({
    required ApiResponseEntity first,
    required String itemsPath,
    required List<Object?> items,
    required Duration duration,
    required bool truncated,
  }) {
    final document = jsonDecode(utf8.decode(first.bodyBytes, allowMalformed: true));
    final merged = JsonPathEditor.set(document, itemsPath, items);
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(merged)));
    return ApiResponseEntity(
      statusCode: first.statusCode,
      statusMessage: first.statusMessage,
      headers: {
        for (final entry in first.headers.entries)
          // The length of the first page is no longer true.
          entry.key: entry.key.toLowerCase() == 'content-length' ? '${bytes.length}' : entry.value,
      },
      bodyBytes: bytes,
      duration: duration,
      truncated: truncated,
      setCookies: first.setCookies,
    );
  }
}
