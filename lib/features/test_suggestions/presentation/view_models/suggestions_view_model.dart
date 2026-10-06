import 'package:flutter/foundation.dart';
import '../../../../core/enums/http_method.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../domain/entities/test_suggestion.dart';
import '../../domain/services/assertion_dedupe.dart';
import '../../domain/services/parsed_response.dart';
import '../../domain/services/stability_probe.dart';
import '../../domain/services/test_suggester.dart';

/// What the last "Add" put into the Tests tab, so one press of Undo takes exactly that out again.
final class AddedTests {
  final int count;
  final List<String> _keys;
  const AddedTests._(this.count, this._keys);
}

/// Backs the "Suggestions" half of the Suggest tests tab: the proposals for one response, which of them are ticked,
/// the stability probe (sending the request once more to find values that change by themselves), and writing the
/// ticked ones into the request's Tests tab.
final class SuggestionsViewModel with ChangeNotifier {
  final int requestId;
  final ApiResponseEntity response;
  final RequestScriptsRepository _scripts;
  final TestSuggester _suggester;

  /// The saved request, when it can be read (it loads after the tab opens): what the stability probe sends again.
  final ApiRequestEntity? Function() _request;

  /// Sends [request] once more; null where that cannot be done.
  final Future<ApiResponseEntity> Function(ApiRequestEntity request)? _send;

  /// The production lock: asks the person before a data-changing request goes out. Null means nothing to ask.
  final Future<bool> Function(ApiRequestEntity request)? _confirmSend;

  /// Told after the request's tests were written, so a Tests tab that is open reads them again.
  final Future<void> Function(int requestId) _afterWrite;

  SuggestionsViewModel({
    required this.requestId,
    required this.response,
    required RequestScriptsRepository scripts,
    ApiRequestEntity? Function()? request,
    Future<ApiResponseEntity> Function(ApiRequestEntity request)? send,
    Future<bool> Function(ApiRequestEntity request)? confirmSend,
    Future<void> Function(int requestId)? afterWrite,
    TestSuggester suggester = const TestSuggester(),
  })  : _scripts = scripts,
        _request = request ?? (() => null),
        _send = send,
        _confirmSend = confirmSend,
        _afterWrite = afterWrite ?? ((_) async {}),
        _suggester = suggester;

  SuggestionResult result = SuggestionResult.empty;
  bool loaded = false;
  bool adding = false;
  bool probing = false;

  /// The person accepted that sending a request that is not a read once more may change data.
  bool unsafeOptIn = false;

  /// What happened to the last probe, when it did not simply work.
  String? probeProblem;
  AddedTests? lastAdded;
  String? error;

  final Set<String> selected = {};

  /// Ids of the proposals the request already has, whatever the spelling.
  Set<String> alreadyThere = const {};
  List<AssertionEntity> _existing = const [];
  ApiResponseEntity? _second;
  StabilityReport? _stability;
  bool _disposed = false;

  Future<void> load() async {
    try {
      final current = await _scripts.get(requestId);
      _existing = ScriptsJsonCodec.decodeAssertions(current?.assertionsJson ?? '[]');
    } catch (e) {
      error = 'The request\'s tests could not be read: ${SecretMasker.maskMessage('$e')}';
    }
    _recompute(first: true);
    loaded = true;
    _notify();
  }

  // --- what is proposed ----------------------------------------------------------

  void _recompute({bool first = false}) {
    result = _suggester.suggest(response, probe: _second);
    alreadyThere = {
      for (final s in result.suggestions)
        if (_existing.any((e) => AssertionDedupe.same(e, s.assertion))) s.id,
    };
    final ids = {for (final s in result.suggestions) s.id};
    if (first) {
      selected
        ..clear()
        ..addAll([for (final s in result.suggestions) if (s.recommended && !alreadyThere.contains(s.id)) s.id]);
    } else {
      selected.removeWhere((id) => !ids.contains(id) || alreadyThere.contains(id));
    }
    _stability = _second == null ? null : _compare(response, _second!);
  }

  static StabilityReport? _compare(ApiResponseEntity a, ApiResponseEntity b) {
    final first = ParsedResponse.of(a);
    final second = ParsedResponse.of(b);
    if (!first.isJson || !second.isJson || first.status ~/ 100 != second.status ~/ 100) return null;
    return StabilityProbe.compare(first.json, second.json);
  }

  /// What a second response showed to change by itself; null before one was fetched or when it could not be compared.
  StabilityReport? get stability => _stability;

  bool isSelected(String id) => selected.contains(id);

  bool canSelect(String id) => !alreadyThere.contains(id);

  int get selectedCount => selected.length;

  void toggle(String id) {
    if (!canSelect(id)) return;
    if (!selected.remove(id)) selected.add(id);
    _notify();
  }

  void selectRecommended() {
    selected
      ..clear()
      ..addAll([for (final s in result.suggestions) if (s.recommended && canSelect(s.id)) s.id]);
    _notify();
  }

  void selectAll() {
    selected
      ..clear()
      ..addAll([for (final s in result.suggestions) if (canSelect(s.id)) s.id]);
    _notify();
  }

  void selectNone() {
    selected.clear();
    _notify();
  }

  /// The proposals of [group], in order.
  List<TestSuggestion> inGroup(SuggestionGroup group) => [for (final s in result.suggestions) if (s.group == group) s];

  // --- the stability probe -------------------------------------------------------

  ApiRequestEntity? get request => _request();

  /// Whether the request is a read, so sending it again changes nothing on the server.
  bool get methodIsSafe {
    final method = request?.method;
    return method == HttpMethod.get || method == HttpMethod.head || method == HttpMethod.options;
  }

  bool get canSendAgain => _send != null && request != null;

  /// Why "Send again" is off, or null when it is on.
  String? get probeBlockedReason {
    if (_send == null) return 'This request cannot be sent from here.';
    final saved = request;
    if (saved == null) return 'The request is still loading.';
    if (!methodIsSafe && !unsafeOptIn) {
      return '${saved.method.label} can change data on the server. Tick the box to send it again anyway.';
    }
    return null;
  }

  bool get probed => _second != null;

  void setUnsafeOptIn(bool value) {
    unsafeOptIn = value;
    _notify();
  }

  /// Sends the request once more and compares the two answers. A request that is not a read needs the opt-in, and the
  /// production lock asks first, as it does for any send.
  Future<void> sendAgain() async {
    final saved = request;
    final send = _send;
    if (saved == null || send == null || probing || probeBlockedReason != null) return;
    probing = true;
    probeProblem = null;
    _notify();
    try {
      final confirm = _confirmSend;
      if (confirm != null && !await confirm(saved)) {
        probeProblem = 'Not sent: the request was not confirmed.';
        return;
      }
      _second = await send(saved);
      _recompute();
    } catch (e) {
      probeProblem = 'The second request failed: ${SecretMasker.maskMessage('$e')}';
    } finally {
      probing = false;
      _notify();
    }
  }

  // --- adding --------------------------------------------------------------------

  /// Writes the ticked proposals into the request's tests, after what it has and without repeating any of it, and
  /// remembers them for [undo]. Returns how many were added.
  Future<int> addSelected() async {
    if (adding) return 0;
    final chosen = [for (final s in result.suggestions) if (selected.contains(s.id) && canSelect(s.id)) s];
    if (chosen.isEmpty) return 0;
    adding = true;
    error = null;
    _notify();
    try {
      final current = await _scripts.get(requestId) ?? RequestScriptsEntity(requestId: requestId);
      final stored = ScriptsJsonCodec.decodeAssertions(current.assertionsJson);
      final fresh = AssertionDedupe.newOnly(stored, [for (final s in chosen) s.assertion]);
      // New rows get ids of their own: the proposals' ids belong to this session's list.
      final toAdd = [for (final a in fresh) AssertionEntity(type: a.type, path: a.path, expected: a.expected)];
      if (toAdd.isNotEmpty) {
        await _scripts.save(current.copyWith(assertionsJson: ScriptsJsonCodec.encodeAssertions([...stored, ...toAdd])));
        await _afterWrite(requestId);
      }
      _existing = [...stored, ...toAdd];
      lastAdded = toAdd.isEmpty ? null : AddedTests._(toAdd.length, [for (final a in toAdd) AssertionDedupe.keyOf(a)]);
      selected.removeAll([for (final s in chosen) s.id]);
      _recompute();
      return toAdd.length;
    } catch (e) {
      error = 'The tests could not be saved: ${SecretMasker.maskMessage('$e')}';
      return 0;
    } finally {
      adding = false;
      _notify();
    }
  }

  /// Takes out what the last [addSelected] put in, and nothing else: a test the person edited since is left alone.
  Future<void> undo() async {
    final added = lastAdded;
    if (added == null || adding) return;
    adding = true;
    _notify();
    try {
      final current = await _scripts.get(requestId);
      if (current != null) {
        final remaining = added._keys.toList();
        final kept = [
          for (final a in ScriptsJsonCodec.decodeAssertions(current.assertionsJson))
            if (!remaining.remove(AssertionDedupe.keyOf(a))) a,
        ];
        await _scripts.save(current.copyWith(assertionsJson: ScriptsJsonCodec.encodeAssertions(kept)));
        await _afterWrite(requestId);
        _existing = kept;
      }
      lastAdded = null;
      _recompute();
    } catch (e) {
      error = 'The tests could not be restored: ${SecretMasker.maskMessage('$e')}';
    } finally {
      adding = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
