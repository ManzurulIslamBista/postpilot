import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../../core/network/logging_api_client.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../domain/entities/console_entry_entity.dart';

/// In-memory record of every request that left the app this session, newest
/// send first and capped at [maxEntries]. Fed by [LoggingApiClient]; watched by
/// the console dialog. A request is listed as pending from the moment it is
/// sent and settles in place once it responds or fails.
final class RequestConsoleLog with ChangeNotifier implements ApiCallObserver {
  static const maxEntries = 200;

  final List<ConsoleEntryEntity> _entries = [];

  List<ConsoleEntryEntity> get entries => UnmodifiableListView(_entries);
  List<ConsoleEntryEntity> get errors => _entries.where((e) => e.isError).toList();

  @override
  ApiCallCompletion onSend(ApiRequestSpec spec, {required DateTime sentAt}) {
    final pending = _entryFor(spec, sentAt: sentAt);
    _insert(pending);
    notifyListeners();
    return ApiCallCompletion(
      onResponse: (response) => _settle(
        pending,
        _entryFor(
          spec,
          sentAt: sentAt,
          durationMs: response.duration.inMilliseconds,
          statusCode: response.statusCode,
          responseSize: response.sizeBytes,
        ),
      ),
      onError: (error, elapsed) => _settle(
        pending,
        _entryFor(spec, sentAt: sentAt, durationMs: elapsed.inMilliseconds, errorMessage: error.toString()),
      ),
    );
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// The URL here is the resolved one, so a `?api_key=` of the query (and a
  /// `user:password@`) would sit in the list, in what the dialog shows and
  /// in anything copied or exported from it: both it and an error message
  /// that quotes it are masked on the way in.
  ConsoleEntryEntity _entryFor(
    ApiRequestSpec spec, {
    required DateTime sentAt,
    int? durationMs,
    int? statusCode,
    int? responseSize,
    String? errorMessage,
  }) =>
      ConsoleEntryEntity(
        method: spec.method,
        url: SecretMasker.maskUrl(spec.url),
        headersCount: spec.headers.length,
        bodySize: _bodySize(spec.body),
        sentAt: sentAt,
        durationMs: durationMs,
        statusCode: statusCode,
        responseSize: responseSize,
        errorMessage: errorMessage == null ? null : SecretMasker.maskMessage(errorMessage),
      );

  /// Slots [entry] in by send time rather than arrival order, so concurrent
  /// requests that finish out of order still list newest-sent first.
  void _insert(ConsoleEntryEntity entry) {
    final index = _entries.indexWhere((e) => !e.sentAt.isAfter(entry.sentAt));
    _entries.insert(index == -1 ? _entries.length : index, entry);
    if (_entries.length > maxEntries) _entries.removeLast();
  }

  /// Swaps the pending row for its outcome. If the row is gone (the console was
  /// cleared, or the cap pushed it out, while the request was in flight) the
  /// outcome is added afresh instead.
  void _settle(ConsoleEntryEntity pending, ConsoleEntryEntity settled) {
    final index = _entries.indexOf(pending);
    if (index == -1) {
      _insert(settled);
    } else {
      _entries[index] = settled;
    }
    notifyListeners();
  }

  int _bodySize(Object? body) => switch (body) {
        List<int> bytes => bytes.length,
        String text => utf8.encode(text).length,
        _ => 0,
      };
}
