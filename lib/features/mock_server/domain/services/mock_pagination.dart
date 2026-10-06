import 'dart:convert';
import 'mock_http.dart';
import 'mock_spec.dart';

/// How a list is cut into pages.
enum MockPaginationStrategy {
  auto('From the spec', 'Use the list operation\'s own parameters: cursor, offset or page, whichever it declares'),
  none('No paging', 'Every list answers with all its items'),
  page('page + limit', '?page=2&limit=10, pages counted from 1'),
  offset('offset + limit', '?offset=20&limit=10'),
  cursor('cursor + limit', '?cursor=<opaque>&limit=10, the next cursor comes back in the answer');

  const MockPaginationStrategy(this.label, this.description);

  final String label;
  final String description;
}

/// The names a list uses for its paging parameters.
final class MockPageNames {
  final String? page;
  final String? size;
  final String? offset;
  final String? cursor;

  /// The first page number: 0 when the page parameter's schema starts at 0.
  final int firstPage;

  /// The largest page size the schema allows, else null.
  final int? maxSize;

  /// The page size the schema defaults to, else null.
  final int? defaultSize;

  const MockPageNames({this.page, this.size, this.offset, this.cursor, this.firstPage = 1, this.maxSize, this.defaultSize});
}

/// One page of a (filtered) list.
final class MockPage {
  final List<Map<String, dynamic>> items;

  /// Items in the whole filtered list.
  final int total;
  final int page;
  final int size;
  final int offset;
  final int pages;
  final String? nextCursor;

  /// The address of the next and the previous page (`/users?page=2&limit=10`), null when there is none.
  final String? nextUrl;
  final String? previousUrl;
  final bool hasMore;
  final MockPaginationStrategy strategy;

  /// `x-total-count`, and `link` when there are other pages.
  final Map<String, String> headers;

  const MockPage({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
    required this.offset,
    required this.pages,
    required this.nextCursor,
    this.nextUrl,
    this.previousUrl,
    required this.hasMore,
    required this.strategy,
    required this.headers,
  });
}

/// Paging and filtering of the in-memory lists.
abstract final class MockPagination {
  static const _pageNames = ['page', 'pageNumber', 'page_number', 'pageIndex', 'page_index', 'p'];
  static const _sizeNames = ['limit', 'per_page', 'perPage', 'size', 'pageSize', 'page_size', 'take', 'count', 'maxResults', 'max_results'];
  static const _offsetNames = ['offset', 'skip'];
  static const _cursorNames = [
    'cursor', 'after', 'next', 'starting_after', 'startingAfter', 'page_token', 'pageToken', 'continuation', 'next_token', 'nextToken',
  ];

  /// What the operation's declared parameters say about paging.
  static MockPageNames namesOf(Iterable<SpecParameter> parameters) {
    SpecParameter? find(List<String> names) {
      for (final name in names) {
        for (final p in parameters) {
          if (p.location == 'query' && p.name == name) return p;
        }
      }
      return null;
    }

    final page = find(_pageNames);
    final size = find(_sizeNames);
    final minimum = page?.schema['minimum'];
    final maximum = size?.schema['maximum'];
    final def = size?.schema['default'];
    return MockPageNames(
      page: page?.name,
      size: size?.name,
      offset: find(_offsetNames)?.name,
      cursor: find(_cursorNames)?.name,
      firstPage: minimum is num && minimum == 0 ? 0 : 1,
      maxSize: maximum is num ? maximum.toInt() : null,
      defaultSize: def is num ? def.toInt() : null,
    );
  }

  /// The strategy a list's parameters point to: a cursor, else an offset, else a page, else none.
  static MockPaginationStrategy detect(MockPageNames names) {
    if (names.cursor != null) return MockPaginationStrategy.cursor;
    if (names.offset != null) return MockPaginationStrategy.offset;
    if (names.page != null || names.size != null) return MockPaginationStrategy.page;
    return MockPaginationStrategy.none;
  }

  /// [items] whose fields equal the query parameters that name them: `?status=active` keeps the items whose `status`
  /// is `active`, `?status=a&status=b` those that are either. A parameter that names no field filters nothing.
  static List<Map<String, dynamic>> filter(List<Map<String, dynamic>> items, MockRequest request, {Set<String> except = const {}}) {
    if (items.isEmpty || request.query.isEmpty) return items;
    final filters = <String, List<String>>{};
    final keys = {for (final k in items.first.keys) _normal(k): k};
    for (final entry in request.query.entries) {
      if (except.contains(entry.key)) continue;
      final field = keys[_normal(entry.key)];
      if (field != null) filters[field] = entry.value.expand((v) => v.split(',')).toList();
    }
    if (filters.isEmpty) return items;
    return [
      for (final item in items)
        if (filters.entries.every((f) => _matches(item[f.key], f.value))) item,
    ];
  }

  static bool _matches(Object? actual, List<String> wanted) {
    if (actual is List) return actual.any((e) => _matches(e, wanted));
    return wanted.contains(actual == null ? 'null' : '$actual');
  }

  static String _normal(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// The names [filter] must not read as fields: the paging parameters themselves.
  static Set<String> reserved(MockPageNames names) => {?names.page, ?names.size, ?names.offset, ?names.cursor};

  /// One page of [items] for [request]. [strategy] must not be [MockPaginationStrategy.auto] (resolve it with [detect]).
  static MockPage paginate(
    List<Map<String, dynamic>> items,
    MockRequest request, {
    required MockPaginationStrategy strategy,
    required MockPageNames names,
    int fallbackSize = 10,
  }) {
    final total = items.length;
    if (strategy == MockPaginationStrategy.none) {
      return MockPage(
        items: items,
        total: total,
        page: 1,
        size: total,
        offset: 0,
        pages: 1,
        nextCursor: null,
        hasMore: false,
        strategy: strategy,
        headers: const {},
      );
    }

    final sizeName = names.size ?? 'limit';
    var size = _positive(request.queryValue(sizeName)) ?? names.defaultSize ?? fallbackSize;
    final cap = names.maxSize ?? 100;
    if (size > cap) size = cap;

    var offset = 0;
    var page = 1;
    switch (strategy) {
      case MockPaginationStrategy.page:
        final pageName = names.page ?? 'page';
        final number = int.tryParse(request.queryValue(pageName) ?? '');
        page = number == null || number < names.firstPage ? names.firstPage : number;
        offset = (page - names.firstPage) * size;
      case MockPaginationStrategy.offset:
        final value = int.tryParse(request.queryValue(names.offset ?? 'offset') ?? '');
        offset = value == null || value < 0 ? 0 : value;
        page = offset ~/ size + 1;
      case MockPaginationStrategy.cursor:
        offset = decodeCursor(request.queryValue(names.cursor ?? 'cursor'));
        page = offset ~/ size + 1;
      case MockPaginationStrategy.auto || MockPaginationStrategy.none:
        break;
    }
    if (offset > total) offset = total;
    final end = offset + size > total ? total : offset + size;
    final pages = total == 0 ? 1 : (total + size - 1) ~/ size;
    final hasMore = end < total;
    final nextCursor = hasMore ? encodeCursor(end) : null;

    final headers = <String, String>{'x-total-count': '$total'};
    final links = <String>[];
    String? nextUrl;
    String? previousUrl;
    if (hasMore) {
      final next = switch (strategy) {
        MockPaginationStrategy.page => {names.page ?? 'page': '${page + 1}', sizeName: '$size'},
        MockPaginationStrategy.offset => {names.offset ?? 'offset': '$end', sizeName: '$size'},
        _ => {names.cursor ?? 'cursor': nextCursor!, sizeName: '$size'},
      };
      nextUrl = _withQuery(request, next);
      links.add('<$nextUrl>; rel="next"');
    }
    if (offset > 0) {
      final previousOffset = offset - size < 0 ? 0 : offset - size;
      final previous = switch (strategy) {
        MockPaginationStrategy.page => {names.page ?? 'page': '${page - 1 < names.firstPage ? names.firstPage : page - 1}', sizeName: '$size'},
        MockPaginationStrategy.offset => {names.offset ?? 'offset': '$previousOffset', sizeName: '$size'},
        _ => {names.cursor ?? 'cursor': encodeCursor(previousOffset), sizeName: '$size'},
      };
      previousUrl = _withQuery(request, previous);
      links.add('<$previousUrl>; rel="prev"');
    }
    if (links.isNotEmpty) headers['link'] = links.join(', ');

    return MockPage(
      items: items.sublist(offset, end),
      total: total,
      page: page,
      size: size,
      offset: offset,
      pages: pages,
      nextCursor: nextCursor,
      nextUrl: nextUrl,
      previousUrl: previousUrl,
      hasMore: hasMore,
      strategy: strategy,
      headers: headers,
    );
  }

  static int? _positive(String? text) {
    final n = int.tryParse(text ?? '');
    return n == null || n < 1 ? null : n;
  }

  /// An opaque cursor for a position: callers treat it as a token, as they would a real one.
  static String encodeCursor(int offset) => base64Url.encode(utf8.encode('o:$offset')).replaceAll('=', '');

  /// The position a cursor names; 0 for none or a cursor that is not ours.
  static int decodeCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return 0;
    try {
      final padded = cursor.padRight((cursor.length + 3) ~/ 4 * 4, '=');
      final text = utf8.decode(base64Url.decode(padded));
      if (!text.startsWith('o:')) return 0;
      final n = int.tryParse(text.substring(2));
      return n == null || n < 0 ? 0 : n;
    } catch (_) {
      return 0;
    }
  }

  static String _withQuery(MockRequest request, Map<String, String> replace) {
    final pairs = <String>[];
    for (final e in request.query.entries) {
      if (replace.containsKey(e.key)) continue;
      for (final v in e.value) {
        pairs.add('${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(v)}');
      }
    }
    for (final e in replace.entries) {
      pairs.add('${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}');
    }
    return '${request.path}?${pairs.join('&')}';
  }

  /// The value for a meta property of a list envelope that the page answers (`total`, `page`, `hasMore`,
  /// `nextCursor`...), picked by the property's name. Null when the name is not a paging one ([found] false).
  static ({bool found, Object? value}) meta(String property, MockPage page) {
    final key = property.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    switch (key) {
      case 'total' || 'totalcount' || 'totalitems' || 'totalelements' || 'totalresults' || 'numfound' || 'count' || 'resultcount':
        return (found: true, value: page.total);
      case 'page' || 'pagenumber' || 'currentpage' || 'pageindex':
        return (found: true, value: page.page);
      case 'limit' || 'pagesize' || 'perpage' || 'size' || 'take':
        return (found: true, value: page.size);
      case 'totalpages' || 'pages' || 'pagecount' || 'lastpage':
        return (found: true, value: page.pages);
      case 'offset' || 'skip':
        return (found: true, value: page.offset);
      case 'hasmore' || 'hasnext' || 'hasnextpage' || 'more':
        return (found: true, value: page.hasMore);
      case 'nextcursor' || 'nextpagetoken' || 'nexttoken' || 'endcursor' || 'cursor':
        return (found: true, value: page.nextCursor);
      // `next` is a cursor for a cursor-paged list and the address of the next page otherwise.
      case 'next' || 'nexturl' || 'nextlink' || 'nextpageurl':
        return (found: true, value: page.strategy == MockPaginationStrategy.cursor ? page.nextCursor : page.nextUrl);
      case 'previous' || 'prev' || 'previousurl' || 'prevurl' || 'previouspageurl':
        return (found: true, value: page.previousUrl);
    }
    return (found: false, value: null);
  }
}
