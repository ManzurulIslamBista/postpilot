import 'dart:convert';
import '../../../settings/domain/entities/settings_json.dart';

/// How the next page is found from the page just received.
enum PaginationKind {
  /// A `Link: <url>; rel="next"` header (GitHub, many REST APIs).
  linkHeader('Link header (rel="next")'),

  /// A field of the JSON body holding the URL of the next page (`next`, `next_url`, `@odata.nextLink`).
  nextUrl('Next-page URL in the body'),

  /// A token in the body (`nextPageToken`, `next_cursor`) that is sent back as a parameter.
  cursor('Cursor / token'),

  /// A page number that goes up by one (`?page=2`), up to a total of pages when the body gives one.
  page('Page number'),

  /// An offset that goes up by the page size (`?offset=100&limit=100`, an Odoo `search_read`).
  offset('Offset and limit');

  final String label;
  const PaginationKind(this.label);
}

/// Where a page parameter (cursor, page number, offset, limit) is written.
enum PageParamLocation {
  /// A query parameter of the URL.
  query('Query parameter'),

  /// A value in the JSON body, named by a JSON path (`offset`, `params.args[6].offset`).
  body('JSON body');

  final String label;
  const PageParamLocation(this.label);
}

/// Fetch every page of a list in one go and give back ONE response: the items of all pages merged under the same
/// JSON path, everything else (status, headers, other fields) from the first page. Stored under the `pagination`
/// key of the request's settings.
///
/// Which fields apply depends on [kind]: [nextPath] for [PaginationKind.nextUrl] (the URL) and
/// [PaginationKind.cursor] (the token); [param] and [location] for cursor, page and offset ([limitParam] for offset
/// only); [totalPath] for page (the number of pages) and offset (the number of items); [hasMorePath] for any of
/// them (a boolean; false ends the walk).
final class PaginationSettings {
  static const maxPagesLimit = 500;
  static const defaultMaxPages = 20;
  static const maxDelayMs = 60000;
  static const maxMegabytesLimit = 100;
  static const defaultMaxMegabytes = 25;

  final bool enabled;
  final PaginationKind kind;

  /// JSON path of the array holding the items; empty when the body itself is the array.
  final String itemsPath;
  final String nextPath;
  final String hasMorePath;
  final String param;
  final PageParamLocation location;
  final String limitParam;
  final String totalPath;

  /// The number of the first page when the request does not set one (0-based APIs start at 0).
  final int firstPage;
  final int maxPages;
  final int delayMs;

  /// End the walk at the first page without items, and leave that page out.
  final bool stopOnEmpty;

  /// Stop when the pages together are bigger than this, whatever else is left.
  final int maxMegabytes;

  /// Ask the server how many records there are before the first page (an Odoo JSON-2 `search_read` is answered by
  /// `search_count` of the same model and domain), so the last page is known and the pages are numbered "2/7".
  final bool countTotal;

  const PaginationSettings({
    this.enabled = false,
    this.kind = PaginationKind.linkHeader,
    this.itemsPath = '',
    this.nextPath = '',
    this.hasMorePath = '',
    this.param = '',
    this.location = PageParamLocation.query,
    this.limitParam = '',
    this.totalPath = '',
    this.firstPage = 1,
    this.maxPages = defaultMaxPages,
    this.delayMs = 0,
    this.stopOnEmpty = true,
    this.maxMegabytes = defaultMaxMegabytes,
    this.countTotal = false,
  });

  static const none = PaginationSettings();

  factory PaginationSettings.fromJson(Object? json) {
    final map = SettingsJson.objectOf(json);
    const defaults = PaginationSettings();
    String text(String key) => SettingsJson.stringOr(map[key], '').trim();
    return PaginationSettings(
      enabled: SettingsJson.boolOr(map['enabled'], false),
      kind: SettingsJson.enumOr(map['kind'], PaginationKind.values, defaults.kind),
      itemsPath: text('itemsPath'),
      nextPath: text('nextPath'),
      hasMorePath: text('hasMorePath'),
      param: text('param'),
      location: SettingsJson.enumOr(map['location'], PageParamLocation.values, defaults.location),
      limitParam: text('limitParam'),
      totalPath: text('totalPath'),
      firstPage: SettingsJson.intOr(map['firstPage'], defaults.firstPage, min: 0, max: 1000000),
      maxPages: SettingsJson.intOr(map['maxPages'], defaults.maxPages, min: 1, max: maxPagesLimit),
      delayMs: SettingsJson.intOr(map['delayMs'], defaults.delayMs, min: 0, max: maxDelayMs),
      stopOnEmpty: SettingsJson.boolOr(map['stopOnEmpty'], defaults.stopOnEmpty),
      maxMegabytes: SettingsJson.intOr(map['maxMegabytes'], defaults.maxMegabytes, min: 1, max: maxMegabytesLimit),
      countTotal: SettingsJson.boolOr(map['countTotal'], defaults.countTotal),
    );
  }

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'kind': kind.name,
        'itemsPath': itemsPath,
        if (nextPath.isNotEmpty) 'nextPath': nextPath,
        if (hasMorePath.isNotEmpty) 'hasMorePath': hasMorePath,
        if (param.isNotEmpty) 'param': param,
        if (location != PageParamLocation.query) 'location': location.name,
        if (limitParam.isNotEmpty) 'limitParam': limitParam,
        if (totalPath.isNotEmpty) 'totalPath': totalPath,
        if (firstPage != 1) 'firstPage': firstPage,
        'maxPages': maxPages,
        if (delayMs != 0) 'delayMs': delayMs,
        'stopOnEmpty': stopOnEmpty,
        'maxMegabytes': maxMegabytes,
        if (countTotal) 'countTotal': true,
      };

  PaginationSettings copyWith({
    bool? enabled,
    PaginationKind? kind,
    String? itemsPath,
    String? nextPath,
    String? hasMorePath,
    String? param,
    PageParamLocation? location,
    String? limitParam,
    String? totalPath,
    int? firstPage,
    int? maxPages,
    int? delayMs,
    bool? stopOnEmpty,
    int? maxMegabytes,
    bool? countTotal,
  }) =>
      PaginationSettings(
        enabled: enabled ?? this.enabled,
        kind: kind ?? this.kind,
        itemsPath: itemsPath ?? this.itemsPath,
        nextPath: nextPath ?? this.nextPath,
        hasMorePath: hasMorePath ?? this.hasMorePath,
        param: param ?? this.param,
        location: location ?? this.location,
        limitParam: limitParam ?? this.limitParam,
        totalPath: totalPath ?? this.totalPath,
        firstPage: _clamp(firstPage ?? this.firstPage, 0, 1000000),
        maxPages: _clamp(maxPages ?? this.maxPages, 1, maxPagesLimit),
        delayMs: _clamp(delayMs ?? this.delayMs, 0, maxDelayMs),
        stopOnEmpty: stopOnEmpty ?? this.stopOnEmpty,
        maxMegabytes: _clamp(maxMegabytes ?? this.maxMegabytes, 1, maxMegabytesLimit),
        countTotal: countTotal ?? this.countTotal,
      );

  /// Nothing set at all: no key is stored.
  bool get isEmpty => this == none;

  /// Why the strategy cannot work as written, or null when it can. Shown in the editor and checked before a walk.
  String? get problem => switch (kind) {
        PaginationKind.linkHeader => null,
        PaginationKind.nextUrl => nextPath.isEmpty ? 'Enter the JSON path of the next-page URL' : null,
        PaginationKind.cursor => nextPath.isEmpty
            ? 'Enter the JSON path of the next-page token'
            : (param.isEmpty ? 'Enter the name of the parameter the token is sent in' : null),
        PaginationKind.page => param.isEmpty ? 'Enter the name of the page parameter' : null,
        PaginationKind.offset => param.isEmpty ? 'Enter the name of the offset parameter' : null,
      };

  /// What the strategy does, in a line, e.g. `Link header · items at data.items · up to 20 pages`.
  String get summary {
    final how = switch (kind) {
      PaginationKind.linkHeader => 'Link header (rel="next")',
      PaginationKind.nextUrl => 'next URL at ${_path(nextPath)}',
      PaginationKind.cursor => 'token at ${_path(nextPath)} sent as ${_where(param)}',
      PaginationKind.page => 'page number in ${_where(param)}${totalPath.isEmpty ? '' : ', total at ${_path(totalPath)}'}',
      PaginationKind.offset =>
        'offset in ${_where(param)}${limitParam.isEmpty ? '' : ', limit in ${_where(limitParam)}'}'
            '${totalPath.isEmpty ? '' : ', total at ${_path(totalPath)}'}${countTotal ? ', total from search_count' : ''}',
    };
    return '$how · items at ${itemsPath.isEmpty ? 'the top level of the body' : itemsPath} · up to $maxPages pages';
  }

  String _where(String name) => location == PageParamLocation.query ? '"$name"' : 'body $name';

  static String _path(String path) => path.isEmpty ? '(not set)' : path;

  @override
  bool operator ==(Object other) => other is PaginationSettings && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

int _clamp(int value, int min, int max) => value < min ? min : (value > max ? max : value);
