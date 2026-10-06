import 'dart:convert';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../entities/pagination_settings.dart';
import 'json_path_editor.dart';
import 'pagination_engine.dart';

/// A strategy found in a response, to be shown and confirmed before it is used.
final class PaginationDetection {
  /// The strategy, not yet [PaginationSettings.enabled]: the person confirms it.
  final PaginationSettings settings;

  /// The request only reads (an Odoo `search_read` over POST), so fetching more pages of it changes nothing and
  /// the "repeating is safe" box can be ticked along with the strategy.
  final bool readOnlyPost;

  const PaginationDetection(this.settings, {this.readOnlyPost = false});

  /// What it found, in a line (see [PaginationSettings.summary]).
  String get summary => settings.summary;
}

/// Looks at a request and the first response it got and works out how the rest of the list is fetched: a `Link`
/// header, a next-page URL or token in the body, a page number with a total, an offset with a limit, or an Odoo
/// `search_read` with its `limit`. Heuristics over the names common APIs use; the person can change what it finds.
abstract final class PaginationDetector {
  /// The strategy for [response] (what [request] got), or null when it shows no sign of more pages.
  static PaginationDetection? detect(ApiRequestEntity request, ApiResponseEntity response) {
    final body = PageItems.decode(response);
    final odoo = _odoo(request);
    if (odoo != null) return odoo;
    if (!body.valid) return null;
    final json = body.value;
    final items = _itemsPath(json);
    if (items == null) return null;

    final fetched = FetchedPage(request: request, response: response, json: json, itemCount: 0);
    if (LinkHeader.next(fetched.header('link')) != null) {
      return PaginationDetection(PaginationSettings(kind: PaginationKind.linkHeader, itemsPath: items));
    }
    if (json is! Map) return null;

    final containers = _containers(json);
    final hasMore = _find(containers, _hasMoreNames) ?? '';

    final url = _findUrl(containers);
    if (url != null) {
      return PaginationDetection(
        PaginationSettings(kind: PaginationKind.nextUrl, itemsPath: items, nextPath: url, hasMorePath: hasMore),
      );
    }

    final cursor = _findCursor(containers);
    if (cursor != null) {
      return PaginationDetection(PaginationSettings(
        kind: PaginationKind.cursor,
        itemsPath: items,
        nextPath: cursor.path,
        param: cursor.param,
        location: _locationOf(request, cursor.param),
        hasMorePath: hasMore,
      ));
    }

    final page = _find(containers, _pageNames);
    final totalPages = _find(containers, _totalPagesNames);
    if (page != null && (totalPages != null || hasMore.isNotEmpty)) {
      final param = _normal(_lastKey(page)) == 'pagenumber' ? 'pageNumber' : 'page';
      return PaginationDetection(PaginationSettings(
        kind: PaginationKind.page,
        itemsPath: items,
        param: param,
        location: _locationOf(request, param),
        totalPath: totalPages ?? '',
        hasMorePath: hasMore,
        // An API that answers `page: 0` counts from 0.
        firstPage: JsonPathEditor.read(json, page) == 0 ? 0 : 1,
      ));
    }

    final offset = _find(containers, _offsetNames);
    final limit = _find(containers, _limitNames);
    final total = _find(containers, _totalNames);
    if (offset != null && (limit != null || total != null)) {
      final param = _lastKey(offset);
      final location = _locationOf(request, param);
      final limitName = limit == null ? '' : _lastKey(limit);
      // The limit is only a parameter to follow when the request sets it itself.
      final followsLimit =
          limitName.isNotEmpty && _locationOf(request, limitName) == location && _requestSets(request, limitName);
      return PaginationDetection(PaginationSettings(
        kind: PaginationKind.offset,
        itemsPath: items,
        param: param,
        location: location,
        limitParam: followsLimit ? limitName : '',
        totalPath: total ?? '',
        hasMorePath: hasMore,
      ));
    }
    return null;
  }

  // --- Odoo ---------------------------------------------------------------------------------------------------

  static final _json2 = RegExp(r'/json/2/[^/?#\s]+/search_read(?:[/?#]|$)', caseSensitive: false);
  static final _datasetSearchRead = RegExp(r'/web/dataset/search_read(?:[/?#]|$)', caseSensitive: false);

  /// Where an Odoo `search_read` keeps its `offset` and `limit` (`holder`, a body path; empty for the top level),
  /// and where its answer has the records (`items`) and their number (`total`); null when [request] is none.
  static ({String holder, String items, String total})? _odooShape(ApiRequestEntity request, Map body) {
    if (_json2.hasMatch(request.url)) return (holder: '', items: '', total: '');
    if (_datasetSearchRead.hasMatch(request.url)) return (holder: 'params', items: 'result.records', total: 'result.length');
    final params = body['params'];
    if (params is! Map) return null;
    // JSON-RPC execute_kw: args are [db, uid, password, model, method, args, kwargs].
    final args = params['args'];
    if (params['service'] == 'object' && params['method'] == 'execute_kw') {
      return args is List && args.length > 6 && args[4] == 'search_read' && args[6] is Map
          ? (holder: 'params.args[6]', items: 'result', total: '')
          : null;
    }
    if (params['method'] == 'search_read' && params['kwargs'] is Map) {
      return (holder: 'params.kwargs', items: 'result', total: '');
    }
    return null;
  }

  /// An Odoo `search_read` that sets a `limit`: pages by `offset` in the body. Without a limit it returns every
  /// record and there is nothing to page.
  static PaginationDetection? _odoo(ApiRequestEntity request) {
    if (request.method != HttpMethod.post || request.body.type != BodyType.raw) return null;
    final Object? body;
    try {
      body = jsonDecode(request.body.rawText);
    } on FormatException {
      return null;
    }
    if (body is! Map) return null;
    final shape = _odooShape(request, body);
    if (shape == null) return null;

    String at(String name) => shape.holder.isEmpty ? name : '${shape.holder}.$name';
    final limit = JsonPathEditor.read(body, at('limit'));
    if (limit is! int || limit <= 0) return null;
    return PaginationDetection(
      PaginationSettings(
        kind: PaginationKind.offset,
        itemsPath: shape.items,
        param: at('offset'),
        location: PageParamLocation.body,
        limitParam: at('limit'),
        totalPath: shape.total,
        // Only JSON-2 has a `search_count` this can ask in the same way.
        countTotal: _json2.hasMatch(request.url),
      ),
      // Every shape above is a search_read, which only reads.
      readOnlyPost: true,
    );
  }

  // --- the items ----------------------------------------------------------------------------------------------

  static const _itemKeys = [
    'items',
    'data',
    'results',
    'result',
    'records',
    'entries',
    'values',
    'value',
    'rows',
    'list',
    'content',
    'docs',
    'hits',
    'nodes',
  ];

  /// The path of the array the items are in: the body itself when it is an array, else a well-known key, else the
  /// largest array of objects, looking one object level down too (`data.items`, `_embedded.orders`).
  static String? _itemsPath(Object? json) {
    if (json is List) return '';
    if (json is! Map) return null;
    for (final key in _itemKeys) {
      if (json[key] is List) return _step('', key);
    }
    for (final entry in json.entries) {
      final child = entry.value;
      if (child is! Map) continue;
      for (final key in _itemKeys) {
        if (child[key] is List) return _step(_step('', '${entry.key}'), key);
      }
    }
    String? best;
    var bestLength = -1;
    void consider(String path, Object? value) {
      if (value is List && value.isNotEmpty && value.first is Map && value.length > bestLength) {
        best = path;
        bestLength = value.length;
      }
    }

    for (final entry in json.entries) {
      consider(_step('', '${entry.key}'), entry.value);
    }
    if (best != null) return best;
    for (final entry in json.entries) {
      final child = entry.value;
      if (child is! Map) continue;
      for (final inner in child.entries) {
        consider(_step(_step('', '${entry.key}'), '${inner.key}'), inner.value);
      }
    }
    return best;
  }

  // --- the paging fields --------------------------------------------------------------------------------------

  static const _containerKeys = {
    'meta',
    'pagination',
    'paging',
    'pageinfo',
    'links',
    'page',
    'data',
    'result',
    'response',
    'metadata',
    'info',
    'cursor',
  };

  /// The body and the objects inside it that usually hold paging fields, each with its path.
  static List<({String path, Map map})> _containers(Map json) => [
        (path: '', map: json),
        for (final entry in json.entries)
          if (entry.value is Map && _containerKeys.contains(_normal('${entry.key}')))
            (path: _step('', '${entry.key}'), map: entry.value as Map),
      ];

  static const _nextUrlNames = {'next', 'nexturl', 'nextpageurl', 'nextlink', 'nextpagelink', 'odatanextlink', 'nexthref'};
  static const _hasMoreNames = {'hasmore', 'hasnext', 'hasnextpage', 'more', 'morepages', 'hasmoreitems', 'hasmoreresults'};
  static const _pageNames = {'page', 'currentpage', 'pagenumber', 'pageno'};
  static const _totalPagesNames = {'totalpages', 'pagecount', 'pages', 'lastpage', 'numpages', 'totalpagecount'};
  static const _offsetNames = {'offset', 'skip', 'start'};
  static const _limitNames = {'limit', 'perpage', 'pagesize', 'size', 'take'};
  static const _totalNames = {'total', 'totalcount', 'totalresults', 'totalitems', 'totalrecords', 'count', 'length'};

  /// Which parameter a token field is sent back in.
  static const _cursorParams = {
    'nextpagetoken': 'pageToken',
    'nextcursor': 'cursor',
    'cursor': 'cursor',
    'nexttoken': 'next_token',
    'nextpagecursor': 'cursor',
    'continuationtoken': 'continuationToken',
    'next': 'cursor',
  };

  /// The path of the first scalar field in [containers] whose name (case, `_` and `-` ignored) is in [names].
  static String? _find(List<({String path, Map map})> containers, Set<String> names) {
    for (final container in containers) {
      for (final entry in container.map.entries) {
        if (names.contains(_normal('${entry.key}')) && entry.value is! Map && entry.value is! List) {
          return _step(container.path, '${entry.key}');
        }
      }
    }
    return null;
  }

  /// A field holding the URL of the next page: a string that is one, or a HAL link object with an `href`.
  static String? _findUrl(List<({String path, Map map})> containers) {
    for (final container in containers) {
      for (final entry in container.map.entries) {
        if (!_nextUrlNames.contains(_normal('${entry.key}'))) continue;
        final value = entry.value;
        final path = _step(container.path, '${entry.key}');
        if (value is String && _looksLikeUrl(value)) return path;
        if (value is Map && value['href'] is String && _looksLikeUrl(value['href'] as String)) return _step(path, 'href');
      }
    }
    return null;
  }

  static ({String path, String param})? _findCursor(List<({String path, Map map})> containers) {
    for (final container in containers) {
      for (final entry in container.map.entries) {
        final name = _normal('${entry.key}');
        final param = _cursorParams[name];
        final value = entry.value;
        if (param == null || (value != null && value is! String && value is! num)) continue;
        // `next` is a token only when it is not a URL (a URL is the next-page URL strategy).
        if (name == 'next' && value is String && _looksLikeUrl(value)) continue;
        return (path: _step(container.path, '${entry.key}'), param: param);
      }
    }
    return null;
  }

  static bool _looksLikeUrl(String text) => RegExp(r'^(https?://|/|\?)', caseSensitive: false).hasMatch(text.trim());

  /// Where the request itself carries [name]: the body when a JSON body has it, otherwise the query.
  static PageParamLocation _locationOf(ApiRequestEntity request, String name) {
    if (request.queryParams.any((p) => p.key.trim() == name) || request.url.contains('$name=')) {
      return PageParamLocation.query;
    }
    final body = request.body;
    if (body.type == BodyType.raw) {
      try {
        final decoded = jsonDecode(body.rawText);
        if (decoded is Map && decoded.containsKey(name)) return PageParamLocation.body;
      } on FormatException {
        // not JSON: the query it is
      }
    }
    return PageParamLocation.query;
  }

  static bool _requestSets(ApiRequestEntity request, String name) =>
      request.queryParams.any((p) => p.enabled && p.key.trim() == name) ||
      request.url.contains('$name=') ||
      (request.body.type == BodyType.raw && request.body.rawText.contains('"$name"'));

  static String _normal(String key) => key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// The last key of a path as written in the response (`meta.total_pages` is `total_pages`).
  static String _lastKey(String path) {
    final quoted = RegExp(r'\["([^"]*)"\]$').firstMatch(path);
    if (quoted != null) return quoted[1]!;
    return path.substring(path.lastIndexOf('.') + 1);
  }

  /// [key] appended to [parent], quoted when it has characters a plain path step cannot (`@odata.nextLink`).
  static String _step(String parent, String key) {
    final plain = RegExp(r'^[A-Za-z0-9_$-]+$').hasMatch(key);
    if (plain) return parent.isEmpty ? key : '$parent.$key';
    return '$parent["$key"]';
  }
}
