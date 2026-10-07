import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/utils/file_download.dart';
import '../../device_helper/data/network_info.dart';
import '../../request_builder/domain/entities/api_request_entity.dart';
import '../../request_builder/domain/entities/request_auth.dart';
import '../data/recorder_engine.dart';
import '../domain/services/lan_addresses.dart';
import '../domain/services/recorded_request_mapper.dart';
import '../domain/services/recorder_connect.dart';
import '../domain/services/recorder_headers.dart';
import '../domain/services/recording_buffer.dart';
import '../domain/services/recording_collection_builder.dart';
import '../domain/services/recording_exports.dart';
import '../domain/services/traffic_masking.dart';
import '../domain/usecases/create_collection_from_recording_usecase.dart';

/// The traffic recorder as the app sees it: one instance for the whole session, so it keeps recording after its dialog is
/// closed. Holds the form, the running engine and the recorded calls (real values; every view, copy and export of them goes
/// through [TrafficMasking] unless [showRealValues] is on, which is never saved).
final class TrafficRecorderViewModel with ChangeNotifier {
  final CreateCollectionFromRecordingUseCase _createCollection;
  final RecorderEngine Function() _createEngine;
  final Future<List<LocalAddress>> Function() _lookupAddresses;
  final Future<String?> Function({required String fileName, required Uint8List bytes, required String mimeType}) _saveFile;
  final DateTime Function() _now;
  RecorderEngine? _engine;
  StreamSubscription<RecordedExchange>? _sub;

  /// [createEngine], [lookupAddresses] and [saveFile] replace the socket engine, the network lookup and the file dialog in
  /// tests.
  TrafficRecorderViewModel(
    this._createCollection, {
    RecorderEngine Function()? createEngine,
    Future<List<LocalAddress>> Function()? lookupAddresses,
    Future<String?> Function({required String fileName, required Uint8List bytes, required String mimeType})? saveFile,
    DateTime Function()? now,
    int maxExchanges = 1000,
  })  : _createEngine = createEngine ?? RecorderEngine.create,
        _lookupAddresses = lookupAddresses ?? RecorderAddresses.lookup,
        _saveFile = saveFile ?? downloadFile,
        _now = now ?? DateTime.now,
        buffer = RecordingBuffer(maxCount: maxExchanges);

  bool get isSupported => RecorderEngine.isSupported;
  bool get isRunning => _engine?.isRunning ?? false;
  int? get port => _engine?.isRunning == true ? _engine?.port : null;

  // --- the form ---------------------------------------------------------------------------------

  String upstreamText = '';
  String portText = '8099';

  /// Listen on every network interface, so a phone on the same Wi-Fi can reach the recorder.
  bool allowOtherDevices = false;
  bool allowSelfSigned = false;
  bool rewriteHostHeaders = true;
  bool keepResponsesReadable = true;

  String? error;
  bool isBusy = false;

  /// What the running (or last) recorder forwards to, and this computer's addresses a phone could use.
  Uri? upstream;
  List<LocalAddress> addresses = const [];

  /// Whether the running recorder listens on every interface (it can differ from [allowOtherDevices] after a change).
  bool get listensForOtherDevices => _engine?.config?.listensOnAllInterfaces ?? false;

  // --- what was recorded --------------------------------------------------------------------------

  final RecordingBuffer buffer;

  /// Calls that went through while recording was paused: forwarded, not recorded.
  int missedWhilePaused = 0;
  bool paused = false;

  /// Real tokens in the views and copies, for this session only. Never saved anywhere.
  bool showRealValues = false;
  String filter = '';
  int? selectedId;
  final Set<int> checkedIds = {};

  int get recordedCount => buffer.length;

  /// What the table shows, newest first: the calls that match [filter] (method, path, status, host).
  List<RecordedExchange> get visible {
    final needle = filter.trim().toLowerCase();
    final all = buffer.items.reversed;
    if (needle.isEmpty) return all.toList();
    return [
      for (final e in all)
        if ('${e.method} ${e.path} ${e.status} ${e.statusMessage}'.toLowerCase().contains(needle)) e,
    ];
  }

  RecordedExchange? get selected => selectedId == null ? null : buffer.byId(selectedId!);

  /// The calls a collection or HAR file is made from: the ticked ones, else every call the table shows.
  List<RecordedExchange> get exportSource {
    if (checkedIds.isNotEmpty) {
      return [
        for (final e in buffer.items)
          if (checkedIds.contains(e.id)) e,
      ];
    }
    return visible.reversed.toList();
  }

  bool get hasTicked => checkedIds.isNotEmpty;

  /// The address to give the app: the network address when other devices may connect, localhost otherwise.
  String? get primaryUrl {
    final p = port;
    if (p == null) return null;
    return RecorderConnect.primaryUrl(port: p, allowOtherDevices: listensForOtherDevices, addresses: addresses);
  }

  List<RecorderConnectOption> get connectOptions {
    final p = port;
    if (p == null) return const [];
    return RecorderConnect.options(port: p, allowOtherDevices: listensForOtherDevices, addresses: addresses);
  }

  /// The upstream's base address as a request URL starts with it (path prefix included, no trailing slash).
  String? get baseUrl {
    final u = upstream;
    return u == null ? null : '${RecorderHeaders.originOf(u)}${u.path.replaceAll(RegExp(r'/+$'), '')}';
  }

  // --- start and stop ------------------------------------------------------------------------------

  Future<void> start() async {
    if (isBusy || isRunning) return;
    final problem = RecorderConfig.upstreamProblem(upstreamText);
    if (problem != null) return _fail(problem);
    final chosenPort = int.tryParse(portText.trim());
    if (chosenPort == null || chosenPort < 0 || chosenPort > 65535) {
      return _fail('The port must be a number between 1 and 65535 (0 picks a free one).');
    }
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      final engine = _engine ??= _createEngine();
      final config = RecorderConfig(
        upstream: RecorderConfig.parseUpstream(upstreamText)!,
        host: allowOtherDevices ? RecorderConfig.allInterfaces : RecorderConfig.loopbackHost,
        port: chosenPort,
        allowSelfSigned: allowSelfSigned,
        rewriteHostHeaders: rewriteHostHeaders,
        keepResponsesReadable: keepResponsesReadable,
      );
      await engine.start(config);
      upstream = config.upstream;
      _detach();
      _sub = engine.exchanges.listen(_onExchange);
      addresses = await _lookupAddresses();
    } on StateError catch (e) {
      error = e.message;
    } catch (e) {
      error = "Couldn't start the recorder (${e.runtimeType}).";
    }
    isBusy = false;
    notifyListeners();
  }

  Future<void> stop() async {
    if (isBusy || _engine == null) return;
    isBusy = true;
    notifyListeners();
    try {
      _detach();
      await _engine?.stop();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Stops listening to the engine's calls. The cancel is not awaited: nothing depends on it, and a subscription whose
  /// cancel never completes (a fake async zone) must not leave the recorder stuck in its busy state.
  void _detach() {
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  void _fail(String message) {
    error = message;
    notifyListeners();
  }

  void _onExchange(RecordedExchange exchange) {
    if (paused) {
      missedWhilePaused++;
    } else {
      buffer.add(exchange);
      _forgetEvicted();
    }
    notifyListeners();
  }

  /// A call pushed out of the ring buffer cannot stay ticked or selected.
  void _forgetEvicted() {
    if (buffer.dropped == 0) return;
    final ids = {for (final e in buffer.items) e.id};
    checkedIds.removeWhere((id) => !ids.contains(id));
    if (selectedId != null && !ids.contains(selectedId)) selectedId = null;
  }

  // --- the table -------------------------------------------------------------------------------------

  void togglePause() {
    paused = !paused;
    if (!paused) missedWhilePaused = 0;
    notifyListeners();
  }

  void clear() {
    buffer.clear();
    checkedIds.clear();
    selectedId = null;
    missedWhilePaused = 0;
    notifyListeners();
  }

  void setFilter(String text) {
    filter = text;
    notifyListeners();
  }

  void select(int? id) {
    selectedId = id;
    notifyListeners();
  }

  void toggleChecked(int id, bool checked) {
    checked ? checkedIds.add(id) : checkedIds.remove(id);
    notifyListeners();
  }

  /// Ticks every call the table shows, or clears the ticks when they are all ticked already.
  void toggleCheckAllVisible() {
    final ids = [for (final e in visible) e.id];
    if (ids.isNotEmpty && ids.every(checkedIds.contains)) {
      checkedIds.removeAll(ids);
    } else {
      checkedIds.addAll(ids);
    }
    notifyListeners();
  }

  void setShowRealValues(bool value) {
    showRealValues = value;
    notifyListeners();
  }

  // --- what the views show -----------------------------------------------------------------------------

  List<RecordedHeader> headersFor(List<RecordedHeader> headers) => TrafficMasking.headers(headers, reveal: showRealValues);

  String bodyFor(String text) => TrafficMasking.body(text, reveal: showRealValues);

  String pathFor(RecordedExchange e) => TrafficMasking.url(e.path, reveal: showRealValues);

  String urlFor(RecordedExchange e) => TrafficMasking.url(e.url, reveal: showRealValues);

  String curlFor(RecordedExchange e) => RecordingCurl.build(e, reveal: showRealValues);

  // --- what leaves the recorder ------------------------------------------------------------------------

  /// The request "Resend in PostPilot" opens: the real upstream address, no credential (secret headers and fields are
  /// `{{variables}}`, named in [secrets]), the ids of the path kept as they were.
  ({ApiRequestEntity request, Set<String> secrets}) resendRequestFor(RecordedExchange e) {
    final draft = RecordedRequestMapper.map(e, baseUrl: baseUrl ?? '', useBaseUrlVariable: false, templatePath: false);
    return (
      request: ApiRequestEntity(
        id: 0,
        collectionId: 0,
        folderId: null,
        name: draft.name,
        method: draft.method,
        url: draft.url,
        headers: draft.headers,
        queryParams: const [],
        body: draft.body,
        auth: const RequestAuth(),
      ),
      secrets: draft.secretVariables,
    );
  }

  /// A collection name proposed for the recording.
  String get suggestedCollectionName {
    final host = upstream?.host ?? '';
    return host.isEmpty ? 'Recorded traffic' : 'Recorded from $host';
  }

  /// What creating a collection from [source] with [options] would make, without making it.
  RecordingPlan previewPlan(RecordingOptions options, {List<RecordedExchange>? source}) => RecordingCollectionBuilder.build(
        source ?? exportSource,
        baseUrl: baseUrl ?? '',
        options: options,
      );

  /// Creates the collection; null when it failed, with [error] set.
  Future<RecordedCollectionResult?> createCollection(RecordingOptions options, {List<RecordedExchange>? source}) async {
    if (isBusy) return null;
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      return await _createCollection(previewPlan(options, source: source));
    } catch (e) {
      error = "Couldn't create the collection: ${_short(e)}";
      return null;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Saves [source] (default: the ticked or shown calls) as a HAR file; credentials are masked. The written path, null on the
  /// web or when nothing was saved.
  Future<String?> saveHar({List<RecordedExchange>? source}) async {
    final calls = source ?? exportSource;
    if (calls.isEmpty) return null;
    final stamp = _now().toIso8601String().replaceAll(RegExp(r'[^0-9T]'), '').replaceFirst('T', '-');
    try {
      return await _saveFile(
        fileName: 'recording-${stamp.substring(0, 15)}.har',
        bytes: Uint8List.fromList(utf8.encode(RecordingHar.export(calls))),
        mimeType: 'application/json',
      );
    } catch (e) {
      error = "Couldn't save the HAR file: ${_short(e)}";
      notifyListeners();
      return null;
    }
  }

  static String _short(Object e) {
    final text = e.toString().replaceAll(RegExp(r'\s+'), ' ');
    return text.length > 140 ? '${text.substring(0, 140)}...' : text;
  }

  @override
  void dispose() {
    _detach();
    _engine?.dispose();
    super.dispose();
  }
}
