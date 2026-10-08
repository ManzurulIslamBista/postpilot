import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../auth_renewal/domain/services/relogin_policy.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../domain/entities/cleanup_settings.dart';
import '../../domain/services/cleanup_planner.dart';

/// What the "Clean up what this request creates" section of a request's Settings tab needs to know about the request
/// around it: the request itself (is it an Odoo create?), the other requests of its collection that could be the undo,
/// and the last answer it got, to recognise a REST create. It reads and never writes: the setting itself is saved by the
/// Settings tab's own view model, the one writer of that row while the tab is open, so an edit here can never be undone
/// by a stale copy of it (or undo an edit made there).
final class CleanupSectionViewModel with ChangeNotifier {
  final Future<ApiRequestEntity?> Function(int requestId) _findRequest;
  final Future<List<ReloginCandidate<RequestSummaryEntity>>> Function(int collectionId) _candidates;

  /// The last response this request got in this session.
  final ApiResponseEntity? Function(int requestId)? _lastResponse;

  ApiRequestEntity? _request;
  List<String> _undoRequests = const [];
  int? _requestId;
  bool _disposed = false;

  bool isLoading = false;

  CleanupSectionViewModel({required this._findRequest, required this._candidates, this._lastResponse});

  ApiRequestEntity? get request => _request;

  /// The other requests of the collection that could undo this one, as `Folder/Name`.
  List<String> get undoRequests => _undoRequests;

  /// What could be switched on with one click, for a request that looks like a create; null when nothing fits or
  /// [current] already is it.
  CleanupSuggestion? suggestionFor(CleanupSettings current) {
    final request = _request;
    if (request == null) return null;
    final response = _lastResponse?.call(request.id);
    return CleanupSuggester.suggest(
      request,
      current,
      lastBody: response == null ? null : utf8.decode(response.bodyBytes, allowMalformed: true),
      lastStatus: response?.statusCode,
    );
  }

  Future<void> load(int requestId) async {
    _requestId = requestId;
    _request = null;
    _undoRequests = const [];
    isLoading = true;
    notifyListeners();

    ApiRequestEntity? request;
    var others = <String>[];
    try {
      request = await _findRequest(requestId);
      if (request != null) {
        others = [
          for (final c in await _candidates(request.collectionId))
            if (c.value.id != requestId) c.path,
        ]..sort();
      }
    } catch (_) {
      // The proposal and the list of undo requests are conveniences: the section still works without them.
    }
    if (_requestId != requestId || _disposed) return; // a newer load() superseded this one

    _request = request;
    _undoRequests = others;
    isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
