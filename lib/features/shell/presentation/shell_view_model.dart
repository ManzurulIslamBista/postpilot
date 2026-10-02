import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../request_builder/domain/entities/api_request_entity.dart';
import '../../request_builder/domain/repositories/request_repository.dart';

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
  int? _selectedRequestId;

  /// Focus target of the sidebar search field (Ctrl/Cmd+K).
  final FocusNode searchFocusNode = FocusNode();

  /// Open tabs, in the order they were opened.
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
  void closeRequest([int? id]) {
    final target = id ?? _selectedRequestId;
    if (target == null) return;
    final index = _openRequestIds.indexOf(target);
    if (index == -1) return;

    _openRequestIds.removeAt(index);
    _summaries.remove(target);
    _subscriptions.remove(target)?.cancel();
    if (_selectedRequestId == target) {
      _selectedRequestId = _openRequestIds.isEmpty ? null : _openRequestIds[index.clamp(0, _openRequestIds.length - 1)];
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

  void _onRequestChanged(int id, ApiRequestEntity? request) {
    // A null row means the request was deleted (directly, or by a cascading
    // folder/collection delete), so its tab has nothing left to show.
    if (request == null) {
      closeRequest(id);
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
