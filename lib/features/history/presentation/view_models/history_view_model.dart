import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/file_download.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../../../request_builder/domain/services/code_generators/curl_generator.dart';
import '../../../request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import '../../../request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import '../../../request_builder/domain/usecases/send_request_usecase.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../../domain/entities/history_filter.dart';
import '../../domain/entities/history_snapshot.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/history_store.dart';
import '../../domain/services/har_exporter.dart';
import '../../domain/services/history_body_diff.dart';
import '../../domain/services/history_curl.dart';
import '../../domain/services/history_har.dart';
import '../../domain/services/history_search.dart';
import '../../domain/services/history_template_expander.dart';

/// Sends a request the way the request builder does.
typedef HistoryResend = Future<ApiResponseEntity> Function(ApiRequestEntity request);

/// Writes [bytes] as a file the person can keep; returns where it went (null in a browser).
typedef HistoryFileSaver = Future<String?> Function({required String fileName, required Uint8List bytes, required String mimeType});

enum HistoryNoticeKind { info, success, warning, error }

/// What the panel tells the person after an action: shown as a strip, not a snackbar, because a dialog covers the snackbar.
final class HistoryNotice {
  final HistoryNoticeKind kind;
  final String message;
  const HistoryNotice(this.kind, this.message);
}

sealed class HistoryListItem {
  const HistoryListItem();
}

final class HistoryDayHeader extends HistoryListItem {
  final String label;
  final int count;
  const HistoryDayHeader(this.label, this.count);
}

final class HistoryEntryItem extends HistoryListItem {
  final HistoryEntryEntity entry;
  const HistoryEntryItem(this.entry);
}

/// Two entries side by side: the older one first.
final class HistoryComparison {
  final HistoryEntryEntity older;
  final HistoryEntryEntity newer;
  final HistoryDetail? olderDetail;
  final HistoryDetail? newerDetail;
  final bool ignoreVolatile;
  final HistoryBodyDiff diff;

  const HistoryComparison({
    required this.older,
    required this.newer,
    required this.olderDetail,
    required this.newerDetail,
    required this.ignoreVolatile,
    required this.diff,
  });
}

/// Backs the History panel: the list with its search and filters, the entry on show with the
/// request it was sent from and the answer, and what can be done with it (open it, edit and send
/// it again, copy it as cURL, compare two, export as HAR).
///
/// It works with any [HistoryRepository]; the details, the search inside bodies and the
/// retention need a [HistoryStore] (the app's own repository is one) and are simply absent
/// without it, so an entry then shows its summary line only.
final class HistoryViewModel with ChangeNotifier {
  final HistoryRepository _repository;
  final RequestRepository? _requests;
  final CollectionRepository? _collections;
  final ResponseExampleRepository? _examples;
  final HistoryResend? _send;
  final HistoryFileSaver _saveFile;
  final Future<HistoryTemplateExpander> Function(int? collectionId)? _expanderFor;
  final Future<String> Function(ApiRequestEntity request)? _resolvedCurl;
  final DateTime Function() _clock;
  final Duration _searchDebounce;

  HistoryViewModel(
    this._repository, {
    RequestRepository? requests,
    CollectionRepository? collections,
    ResponseExampleRepository? examples,
    HistoryResend? send,
    HistoryFileSaver saveFile = downloadFile,
    Future<HistoryTemplateExpander> Function(int? collectionId)? expanderFor,
    Future<String> Function(ApiRequestEntity request)? resolvedCurl,
    DateTime Function()? clock,
    Duration searchDebounce = const Duration(milliseconds: 250),
  })  : _requests = requests,
        _collections = collections,
        _examples = examples,
        _send = send,
        _saveFile = saveFile,
        _expanderFor = expanderFor,
        _resolvedCurl = resolvedCurl,
        _clock = clock ?? DateTime.now,
        _searchDebounce = searchDebounce {
    final repository = _repository;
    final stream = repository is HistoryStore ? repository.watchAll() : repository.watchRecent();
    _sub = stream.listen(_onEntries);
  }

  late final StreamSubscription<List<HistoryEntryEntity>> _sub;
  bool _disposed = false;

  /// Every entry kept, newest first.
  List<HistoryEntryEntity> entries = [];

  HistoryFilter _filter = const HistoryFilter();
  HistoryFilter get filter => _filter;

  /// Entries whose stored text matches the query, from the database (the summary is matched in memory).
  Set<int> _storedMatches = const {};
  Timer? _debounce;
  int _searchToken = 0;
  List<HistoryEntryEntity>? _visible;
  List<HistoryListItem>? _items;

  int? selectedId;
  HistoryDetail? detail;
  bool detailLoading = false;
  final Map<int, HistoryDetail?> _details = {};
  static const _detailCacheSize = 24;

  /// "Select" mode: a checkbox on every row, for comparing two entries or exporting several.
  bool selecting = false;
  final Set<int> checked = {};

  HistoryComparison? comparison;
  bool comparing = false;

  /// A re-send is in flight.
  bool sending = false;
  bool exporting = false;
  HistoryNotice? notice;

  /// After a re-send: select the entry it adds, once it shows up (the id of the newest entry before it).
  int? _selectNewestAfter;

  /// Whether this repository keeps request details at all.
  bool get hasDetails => _repository is HistoryStore;

  void _onEntries(List<HistoryEntryEntity> value) {
    entries = value;
    _invalidate();
    final follow = _selectNewestAfter;
    if (follow != null && value.isNotEmpty && value.first.id > follow) {
      _selectNewestAfter = null;
      unawaited(select(value.first.id));
    } else if (selectedId != null && !value.any((e) => e.id == selectedId)) {
      selectedId = null;
      detail = null;
    }
    checked.removeWhere((id) => !value.any((e) => e.id == id));
    if (!_disposed) notifyListeners();
  }

  void _invalidate() {
    _visible = null;
    _items = null;
  }

  // --- list: filters, search, grouping ----------------------------------------

  /// What the query is matched against: trimmed and lower-cased.
  String get needle => HistorySearch.normalise(_filter.query);

  /// The entries that pass every filter, newest first.
  List<HistoryEntryEntity> get visible => _visible ??= [
        for (final e in entries)
          if (_filter.matchesFacets(e, _clock()) && _matchesQuery(e)) e,
      ];

  bool _matchesQuery(HistoryEntryEntity entry) {
    final text = needle;
    return text.isEmpty || HistorySearch.matchesSummary(entry, text) || _storedMatches.contains(entry.id);
  }

  /// [visible] grouped by day, each group under a header.
  List<HistoryListItem> get items => _items ??= _group(visible);

  List<HistoryListItem> _group(List<HistoryEntryEntity> list) {
    final now = _clock();
    final counts = <String, int>{};
    String key(DateTime t) => '${t.year}-${t.month}-${t.day}';
    for (final e in list) {
      counts.update(key(e.sentAt.toLocal()), (n) => n + 1, ifAbsent: () => 1);
    }
    final out = <HistoryListItem>[];
    String? current;
    for (final e in list) {
      final local = e.sentAt.toLocal();
      final k = key(local);
      if (k != current) {
        current = k;
        out.add(HistoryDayHeader(dayLabel(local, now), counts[k]!));
      }
      out.add(HistoryEntryItem(e));
    }
    return out;
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// "Today", "Yesterday", then "Mon 6 Oct" (with the year when it is not this one).
  static String dayLabel(DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(day.year, day.month, day.day);
    final days = DateTime.utc(today.year, today.month, today.day).difference(DateTime.utc(that.year, that.month, that.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    final base = '${_weekdays[that.weekday - 1]} ${that.day} ${_months[that.month - 1]}';
    return that.year == today.year ? base : '$base ${that.year}';
  }

  /// Methods that occur in the list, in the usual order.
  List<String> get methods {
    const order = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];
    final found = {for (final e in entries) e.method.toUpperCase()};
    return [
      for (final m in order)
        if (found.remove(m)) m,
      ...found.toList()..sort(),
    ];
  }

  /// Collections entries were sent from, by the name they had then.
  List<({int id, String name})> get collections {
    final names = <int, String>{};
    for (final e in entries) {
      final meta = e.meta;
      final id = meta?.collectionId;
      if (id != null) names.putIfAbsent(id, () => meta!.collectionName ?? 'Collection $id');
    }
    return [for (final e in names.entries) (id: e.key, name: e.value)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Types into the search box: the summary lines narrow at once, and the text stored with
  /// each entry (bodies, names) is searched once typing pauses.
  void setQuery(String query) {
    if (query == _filter.query) return;
    _filter = _filter.copyWith(query: query);
    _storedMatches = const {};
    _invalidate();
    _debounce?.cancel();
    final token = ++_searchToken;
    if (needle.isNotEmpty && _repository is HistoryStore) {
      _debounce = Timer(_searchDebounce, () => unawaited(_searchStored(token)));
    }
    notifyListeners();
  }

  Future<void> _searchStored(int token) async {
    final repository = _repository;
    if (repository is! HistoryStore) return;
    final text = needle;
    if (text.isEmpty) return;
    Set<int> ids;
    try {
      ids = await repository.searchStored(text);
    } catch (_) {
      return; // the summary matches still show
    }
    if (_disposed || token != _searchToken) return;
    _storedMatches = ids;
    _invalidate();
    notifyListeners();
  }

  void setStatusClass(HistoryStatusClass? value) => _setFilter(_filter.copyWith(statusClass: value));
  void setMethod(String? value) => _setFilter(_filter.copyWith(method: value));
  void setCollection(int? value) => _setFilter(_filter.copyWith(collectionId: value));
  void setRange(HistoryRange value) => _setFilter(_filter.copyWith(range: value));

  void clearFilters() {
    _debounce?.cancel();
    _searchToken++;
    _storedMatches = const {};
    _setFilter(const HistoryFilter());
  }

  void _setFilter(HistoryFilter next) {
    _filter = next;
    _invalidate();
    notifyListeners();
  }

  // --- the entry on show -------------------------------------------------------

  HistoryEntryEntity? get selected {
    final id = selectedId;
    if (id == null) return null;
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> select(int? id) async {
    if (id == selectedId && comparison == null) return;
    selectedId = id;
    comparison = null;
    detail = null;
    if (id == null) {
      detailLoading = false;
      notifyListeners();
      return;
    }
    detailLoading = true;
    notifyListeners();
    final entry = selected;
    final loaded = entry == null ? null : await detailFor(entry);
    if (_disposed || selectedId != id) return;
    detail = loaded;
    detailLoading = false;
    notifyListeners();
  }

  /// The request snapshot and answer kept for [entry]; null when none were kept.
  Future<HistoryDetail?> detailFor(HistoryEntryEntity entry) async {
    final repository = _repository;
    if (repository is! HistoryStore || !entry.hasDetails) return null;
    if (_details.containsKey(entry.id)) return _details[entry.id];
    HistoryDetail? loaded;
    try {
      loaded = await repository.detailOf(entry.id);
    } catch (_) {
      loaded = null;
    }
    if (_details.length >= _detailCacheSize) _details.remove(_details.keys.first);
    _details[entry.id] = loaded;
    return loaded;
  }

  /// What can be done with [entry]: its stored request, or just its method and URL.
  Future<HistoryRequestSnapshot> snapshotOf(HistoryEntryEntity entry) async =>
      (await detailFor(entry))?.request ?? HistoryRequestSnapshot.bare(entry.method, entry.url);

  void dismissNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  void _tell(HistoryNoticeKind kind, String message) {
    notice = HistoryNotice(kind, message);
    if (!_disposed) notifyListeners();
  }

  // --- selecting several --------------------------------------------------------

  void toggleSelecting() {
    selecting = !selecting;
    if (!selecting) checked.clear();
    notifyListeners();
  }

  void toggleChecked(int id) {
    if (!checked.remove(id)) checked.add(id);
    notifyListeners();
  }

  void clearChecked() {
    checked.clear();
    notifyListeners();
  }

  /// "Compare with...": select mode with [entry] already ticked, waiting for the second.
  void startCompareWith(HistoryEntryEntity entry) {
    selecting = true;
    checked
      ..clear()
      ..add(entry.id);
    notice = const HistoryNotice(HistoryNoticeKind.info, 'Tick one more entry in the list to compare it with this one.');
    notifyListeners();
  }

  static const _volatileKeys = {
    'updated_at', 'created_at', 'updatedat', 'createdat', 'timestamp', 'requestid', 'request_id', 'write_date', 'date',
  };

  /// Compares the two ticked entries' response bodies.
  Future<void> compareChecked({bool? ignoreVolatile}) async {
    if (checked.length != 2 || comparing) return;
    final pair = [for (final e in entries) if (checked.contains(e.id)) e]..sort((a, b) => a.id.compareTo(b.id));
    if (pair.length != 2) return;
    comparing = true;
    notifyListeners();
    final older = await detailFor(pair[0]);
    final newer = await detailFor(pair[1]);
    final ignore = ignoreVolatile ?? comparison?.ignoreVolatile ?? false;
    comparing = false;
    if (_disposed) return;
    comparison = HistoryComparison(
      older: pair[0],
      newer: pair[1],
      olderDetail: older,
      newerDetail: newer,
      ignoreVolatile: ignore,
      diff: HistoryBodyCompare.compare(older?.responseText, newer?.responseText, ignoreKeys: ignore ? _volatileKeys : const {}),
    );
    selectedId = null;
    detail = null;
    notifyListeners();
  }

  void closeComparison() {
    if (comparison == null) return;
    comparison = null;
    notifyListeners();
  }

  // --- actions on an entry --------------------------------------------------------

  /// The collection [snapshot] was sent from, when it still exists under the same name (an id
  /// can mean another collection after the workspace was swapped); null otherwise.
  Future<int?> originCollectionOf(HistoryRequestSnapshot snapshot) async {
    final id = snapshot.meta.collectionId;
    if (id == null) return null;
    final all = await _collectionList();
    for (final c in all) {
      if (c.id == id && (snapshot.meta.collectionName == null || snapshot.meta.collectionName == c.name)) return id;
    }
    return null;
  }

  Future<List<CollectionEntity>> _collectionList() async {
    final repository = _collections ?? (locator.isRegistered<CollectionRepository>() ? locator<CollectionRepository>() : null);
    if (repository == null) return const [];
    return repository.watchCollections().first;
  }

  RequestRepository get _requestRepository => _requests ?? locator<RequestRepository>();

  /// Saves [entry]'s request as a new request of [collectionId] (it never touches the one it came from)
  /// and returns its id, ready to open. With [copy] it is named as a copy made from History.
  Future<int> openAsNewRequest(HistoryEntryEntity entry, {required int collectionId, bool copy = false}) async {
    final snapshot = await snapshotOf(entry);
    final name = copy ? '${snapshot.name} (from history)' : snapshot.name;
    final requests = _requestRepository;
    final id = await requests.createRequest(collectionId: collectionId, name: name);
    await requests.saveRequest(snapshot.toRequest(id: id, collectionId: collectionId, name: name));
    return id;
  }

  /// [openAsNewRequest] under its old name.
  Future<int> openInBuilder(HistoryEntryEntity entry, {required int collectionId}) =>
      openAsNewRequest(entry, collectionId: collectionId);

  /// Sends [entry]'s request again, unchanged. [confirm] is asked first with the request about to go out
  /// (the production lock, and the warning about masked values, live there); false cancels.
  Future<void> resendAsIs(HistoryEntryEntity entry, {required Future<bool> Function(ApiRequestEntity request) confirm}) async {
    if (sending) return;
    final snapshot = await snapshotOf(entry);
    final requestId = await _existingRequestId(snapshot.meta.requestId);
    final collectionId = await originCollectionOf(snapshot);
    final request = snapshot.toRequest(id: requestId ?? 0, collectionId: collectionId ?? 0);
    if (!await confirm(request) || _disposed) return;

    sending = true;
    notice = null;
    _selectNewestAfter = entries.isEmpty ? 0 : entries.first.id;
    notifyListeners();
    try {
      final send = _send ?? locator<SendRequestUseCase>().call;
      final response = await send(request);
      final status = '${response.statusCode}${response.statusMessage.isEmpty ? '' : ' ${response.statusMessage}'}';
      _tell(
        HistoryNoticeKind.success,
        'Sent again: $status in ${response.duration.inMilliseconds} ms. The new entry is at the top of the list.',
      );
    } catch (error) {
      _selectNewestAfter = null;
      _tell(HistoryNoticeKind.error, _describe(error));
    } finally {
      sending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<int?> _existingRequestId(int? id) async {
    if (id == null) return null;
    try {
      return await _requestRepository.findById(id) == null ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// One line for what a failed send threw, masked: the text of an error can quote the URL.
  static String _describe(Object error) {
    final text = switch (error) {
      NetworkException(:final summary?) => summary,
      NetworkException(:final message) => message,
      InvalidRequestException(:final message) => message,
      InvalidUrlException() => "That URL isn't valid: it needs an http(s) scheme and a host.",
      _ => 'The request failed: $error',
    };
    final line = SecretMasker.maskMessage(text).split(RegExp(r'[\r\n]+')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => text);
    return line.trim();
  }

  /// The cURL command of [entry] in the template form: `{{variables}}` as written, masked values masked.
  Future<String> curlTemplate(HistoryEntryEntity entry) async => HistoryCurl.template(await snapshotOf(entry));

  /// The cURL command with the active environment's values filled in. It holds real secrets.
  Future<String> curlResolved(HistoryEntryEntity entry) async {
    final snapshot = await snapshotOf(entry);
    final collectionId = await originCollectionOf(snapshot);
    final request = snapshot.toRequest(id: 0, collectionId: collectionId ?? 0);
    final custom = _resolvedCurl;
    if (custom != null) return custom(request);
    return locator<GenerateCodeSnippetUseCase>()(GenerateCodeSnippetParams(request, const CurlGenerator()));
  }

  void tell(HistoryNoticeKind kind, String message) => _tell(kind, message);

  /// The request [entry] was sent from still exists, so a response can be saved as an example of it.
  Future<bool> canSaveExample(HistoryEntryEntity entry) async {
    if (!entry.hasDetails || entry.statusCode == null) return false;
    final loaded = await detailFor(entry);
    if (loaded == null || !loaded.hasResponseBody) return false;
    return await _existingRequestId(loaded.request.meta.requestId) != null;
  }

  /// Saves the stored response of [entry] as an example of its request.
  Future<void> saveAsExample(HistoryEntryEntity entry) async {
    final loaded = await detailFor(entry);
    final status = entry.statusCode;
    final requestId = await _existingRequestId(loaded?.request.meta.requestId);
    if (loaded == null || !loaded.hasResponseBody || status == null || requestId == null) {
      _tell(HistoryNoticeKind.error, 'This response cannot be saved as an example: its request or its body is no longer there.');
      return;
    }
    final repository = _examples ?? locator<ResponseExampleRepository>();
    final when = entry.sentAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    try {
      await repository.add(ResponseExampleEntity(
        id: 0,
        requestId: requestId,
        name: 'From history ${when.year}-${two(when.month)}-${two(when.day)} ${two(when.hour)}:${two(when.minute)} ($status)',
        statusCode: status,
        headers: {
          if (loaded.responseContentType != null) 'content-type': loaded.responseContentType!,
          if (loaded.responseTruncated) ResponseExampleEntity.truncatedHeader: 'true',
        },
        body: loaded.responseText!,
        savedAt: _clock(),
      ));
      _tell(
        HistoryNoticeKind.success,
        'Saved as an example of "${loaded.request.name}". Credentials in it were masked when it was recorded.',
      );
    } catch (error) {
      _tell(HistoryNoticeKind.error, 'The example could not be saved (${error.runtimeType}).');
    }
  }

  // --- HAR ------------------------------------------------------------------------

  /// The entries a HAR export covers: the ticked ones, else everything the filters show.
  List<HistoryEntryEntity> entriesToExport({required bool selectedOnly}) =>
      selectedOnly ? [for (final e in visible) if (checked.contains(e.id)) e] : visible;

  /// Writes [entriesToExport] (or just [only]) as a HAR file and says where it went. Oldest first, as
  /// browsers write them.
  Future<void> exportHar({required bool selectedOnly, HistoryEntryEntity? only}) async {
    if (exporting) return;
    final list = (only == null ? entriesToExport(selectedOnly: selectedOnly) : [only]).reversed.toList();
    if (list.isEmpty) {
      _tell(HistoryNoticeKind.info, 'There is nothing to export: no entry is shown.');
      return;
    }
    exporting = true;
    notice = null;
    notifyListeners();
    try {
      final expanders = <int?, HistoryTemplateExpander>{};
      final inputs = <HarEntryInput>[];
      for (final entry in list) {
        final loaded = await detailFor(entry);
        final collectionId = loaded?.request.meta.collectionId;
        final expander = expanders[collectionId] ??= await _expander(collectionId);
        inputs.add(HistoryHar.inputFor(entry, loaded, expand: expander.call));
      }
      final bytes = Uint8List.fromList(utf8.encode(HarExporter.export(inputs)));
      final now = _clock();
      String two(int n) => n.toString().padLeft(2, '0');
      final name = 'postpilot-history-${now.year}-${two(now.month)}-${two(now.day)}.har';
      final path = await _saveFile(fileName: name, bytes: bytes, mimeType: 'application/json');
      final count = '${inputs.length} request${inputs.length == 1 ? '' : 's'}';
      _tell(
        HistoryNoticeKind.success,
        path == null
            ? 'Exported $count as $name. Credentials are masked and response headers are not included.'
            : 'Exported $count to $path. Credentials are masked and response headers are not included.',
      );
    } catch (error) {
      _tell(HistoryNoticeKind.error, 'The HAR file could not be written (${error.runtimeType}).');
    } finally {
      exporting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<HistoryTemplateExpander> _expander(int? collectionId) async {
    final custom = _expanderFor;
    if (custom != null) return custom(collectionId);
    if (!locator.isRegistered<BuildVariableResolverUseCase>()) return HistoryTemplateExpander.none;
    try {
      final resolver = await locator<BuildVariableResolverUseCase>()(collectionId ?? 0);
      return HistoryTemplateExpander.safe(resolver, secretKeys: await _flaggedSecretKeys());
    } catch (_) {
      return HistoryTemplateExpander.none;
    }
  }

  /// Variables the user marked secret in the active environment and the globals.
  Future<Set<String>> _flaggedSecretKeys() async {
    final keys = <String>{};
    try {
      if (locator.isRegistered<EnvironmentRepository>()) {
        final environments = locator<EnvironmentRepository>();
        final active = await environments.watchActive().first;
        if (active != null) {
          for (final v in await environments.watchVariables(active.id).first) {
            if (v.isSecret && v.enabled) keys.add(v.key);
          }
        }
      }
      if (locator.isRegistered<GlobalVariableRepository>()) {
        for (final g in await locator<GlobalVariableRepository>().watchAll().first) {
          if (g.isSecret && g.enabled) keys.add(g.key);
        }
      }
    } catch (_) {
      // The names that look secret are still left out.
    }
    return keys;
  }

  // --- housekeeping --------------------------------------------------------------

  /// Removes what the history settings no longer allow (a smaller limit, a shorter retention).
  Future<void> applyRetention() async {
    final repository = _repository;
    if (repository is! HistoryStore) return;
    try {
      await repository.applyRetention();
    } catch (_) {
      // Entries past the limit are removed by the next send instead.
    }
  }

  Future<void> clear() async {
    await _repository.clear();
    _details.clear();
    _storedMatches = const {};
    selectedId = null;
    detail = null;
    checked.clear();
    comparison = null;
    notice = null;
    _invalidate();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _sub.cancel();
    super.dispose();
  }
}
