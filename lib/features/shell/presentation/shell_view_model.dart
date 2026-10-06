import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../request_builder/domain/entities/api_request_entity.dart';
import '../../request_builder/domain/repositories/request_repository.dart';

/// What a keyboard shortcut can ask the visible request tab to do, beyond sending.
enum TabAction {
  /// Puts the cursor in the URL field.
  focusUrl,

  /// Saves the response on screen as an example of the request.
  saveResponseExample,
}

/// Owns "what's open in the main pane" — the ordered request tabs and which
/// one is active — the one piece of state every feature's widgets need to
/// agree on.
final class ShellViewModel with ChangeNotifier {
  final RequestRepository _requestRepository;

  ShellViewModel(this._requestRepository);

  final List<int> _openRequestIds = [];
  final Map<int, RequestSummaryEntity> _summaries = {};
  final Map<int, StreamSubscription<ApiRequestEntity?>> _subscriptions = {};
  final Map<int, VoidCallback> _senders = {};
  final Map<int, VoidCallback> _bodySearches = {};
  final Map<int, Map<TabAction, VoidCallback>> _tabActions = {};
  int? _selectedRequestId;

  /// Pinned tabs sit first, show a pin instead of a close button and survive
  /// "Close others" / "Close all".
  final Set<int> _pinned = {};

  /// Requests whose tab was closed on purpose, newest last, for Ctrl+Shift+T.
  final List<int> _recentlyClosed = [];
  static const _recentlyClosedLimit = 15;

  /// Focus target of the sidebar search field (Ctrl/Cmd+K).
  final FocusNode searchFocusNode = FocusNode();

  bool isPinned(int id) => _pinned.contains(id);
  bool get canReopenClosed => _recentlyClosed.isNotEmpty;

  /// Open tabs: pinned ones first, then in the order they were opened.
  List<int> get openRequestIds => List.unmodifiable(_openRequestIds);

  /// The active tab, or null when nothing is open.
  int? get selectedRequestId => _selectedRequestId;

  /// Name and method shown on a tab; null until the request's first load lands.
  RequestSummaryEntity? tabSummary(int id) => _summaries[id];

  /// Collection and folder holding the active tab's request, so a new request
  /// can be created beside it; null when no tab is open.
  Future<({int collectionId, int? folderId})?> selectedRequestLocation() async {
    final id = _selectedRequestId;
    if (id == null) return null;
    final request = await _requestRepository.findById(id);
    return request == null ? null : (collectionId: request.collectionId, folderId: request.folderId);
  }

  /// Opens [id] in a new tab if it isn't already open, then makes it active.
  void selectRequest(int id) {
    if (!_openRequestIds.contains(id)) {
      _openRequestIds.add(id);
      _subscriptions[id] = _requestRepository.watchById(id).listen((request) => _onRequestChanged(id, request));
    }
    _selectedRequestId = id;
    notifyListeners();
  }

  /// Closes the tab for [id] (the active one when omitted). If it was active,
  /// the tab that slides into its slot — or the last one — becomes active.
  void closeRequest([int? id]) => _close(id ?? _selectedRequestId, remember: true);

  void _close(int? target, {required bool remember}) {
    if (target == null) return;
    final index = _openRequestIds.indexOf(target);
    if (index == -1) return;

    if (remember) {
      _recentlyClosed
        ..remove(target)
        ..add(target);
      if (_recentlyClosed.length > _recentlyClosedLimit) _recentlyClosed.removeAt(0);
    }
    _pinned.remove(target);
    _openRequestIds.removeAt(index);
    _summaries.remove(target);
    _subscriptions.remove(target)?.cancel();
    if (_selectedRequestId == target) {
      _selectedRequestId = _openRequestIds.isEmpty ? null : _openRequestIds[index.clamp(0, _openRequestIds.length - 1)];
    }
    notifyListeners();
  }

  /// Pins [id] to the front, or unpins it (it stays where it is).
  void togglePin(int id) {
    if (!_openRequestIds.contains(id)) return;
    if (_pinned.remove(id)) {
      notifyListeners();
      return;
    }
    _pinned.add(id);
    _openRequestIds.remove(id);
    _openRequestIds.insert(_pinned.where((p) => p != id && _openRequestIds.contains(p)).length, id);
    notifyListeners();
  }

  /// Closes every unpinned tab except [keep].
  void closeOthers(int keep) {
    for (final id in List<int>.of(_openRequestIds)) {
      if (id != keep && !_pinned.contains(id)) _close(id, remember: true);
    }
    if (_openRequestIds.contains(keep)) _selectedRequestId = keep;
    notifyListeners();
  }

  /// Closes the unpinned tabs to the right of [id].
  void closeToRight(int id) {
    final index = _openRequestIds.indexOf(id);
    if (index == -1) return;
    for (final other in _openRequestIds.sublist(index + 1)) {
      if (!_pinned.contains(other)) _close(other, remember: true);
    }
  }

  /// Closes every unpinned tab.
  void closeAll() {
    for (final id in List<int>.of(_openRequestIds)) {
      if (!_pinned.contains(id)) _close(id, remember: true);
    }
  }

  /// Ctrl+Shift+T: opens the most recently closed request that still exists.
  Future<void> reopenClosed() async {
    while (_recentlyClosed.isNotEmpty) {
      final id = _recentlyClosed.removeLast();
      if (_openRequestIds.contains(id)) continue;
      if (await _requestRepository.findById(id) != null) {
        selectRequest(id);
        return;
      }
    }
    notifyListeners();
  }

  /// Each mounted RequestBuilderPage registers its view model's send() so the
  /// shell's shortcut can reach the active tab without holding its view model
  /// (every open tab stays mounted, so a single callback would be ambiguous).
  void registerSender(int requestId, VoidCallback send) => _senders[requestId] = send;

  /// Only removes [send] itself: a page replaced under the same id registers
  /// its new sender before the old page is disposed, and must keep it.
  void unregisterSender(int requestId, VoidCallback send) {
    if (_senders[requestId] == send) _senders.remove(requestId);
  }

  void sendSelected() => _senders[_selectedRequestId]?.call();

  /// Same per-tab registration for "find in the response" (Ctrl/Cmd+F): every
  /// open tab keeps its own response, so the shortcut must reach the visible one.
  void registerBodySearch(int requestId, VoidCallback open) => _bodySearches[requestId] = open;

  void unregisterBodySearch(int requestId, VoidCallback open) {
    if (_bodySearches[requestId] == open) _bodySearches.remove(requestId);
  }

  void findInResponse() => _bodySearches[_selectedRequestId]?.call();

  /// The same per-tab registration for the other shortcut actions of [TabAction].
  void registerTabAction(int requestId, TabAction action, VoidCallback run) =>
      (_tabActions[requestId] ??= {})[action] = run;

  void unregisterTabAction(int requestId, TabAction action, VoidCallback run) {
    final actions = _tabActions[requestId];
    if (actions == null || actions[action] != run) return;
    actions.remove(action);
    if (actions.isEmpty) _tabActions.remove(requestId);
  }

  /// Runs [action] on the active tab; false when no tab is open or it offers none.
  bool runTabAction(TabAction action) {
    final run = _tabActions[_selectedRequestId]?[action];
    run?.call();
    return run != null;
  }

  void focusUrl() => runTabAction(TabAction.focusUrl);
  void saveResponseExample() => runTabAction(TabAction.saveResponseExample);

  /// Ctrl+PageDown: the tab to the right of the active one, wrapping to the first.
  void selectNextTab() => _stepTab(1);

  /// Ctrl+PageUp: the tab to the left of the active one, wrapping to the last.
  void selectPreviousTab() => _stepTab(-1);

  void _stepTab(int step) {
    final current = _selectedRequestId;
    if (current == null || _openRequestIds.length < 2) return;
    final index = _openRequestIds.indexOf(current);
    _selectedRequestId = _openRequestIds[(index + step) % _openRequestIds.length];
    notifyListeners();
  }

  void _onRequestChanged(int id, ApiRequestEntity? request) {
    // A null row means the request was deleted (directly, or by a cascading
    // folder/collection delete), so its tab has nothing left to show.
    if (request == null) {
      _recentlyClosed.remove(id);
      _close(id, remember: false);
      return;
    }
    final current = _summaries[id];
    if (current != null && current.name == request.name && current.method == request.method) return;
    _summaries[id] = RequestSummaryEntity(
      id: id,
      folderId: request.folderId,
      name: request.name,
      method: request.method,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    searchFocusNode.dispose();
    super.dispose();
  }
}
