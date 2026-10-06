import 'dart:async';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/entities/history_snapshot.dart';
import 'package:postpilot/features/history/domain/repositories/history_store.dart';
import 'package:postpilot/features/history/domain/services/history_search.dart';

/// A [HistoryStore] held in memory, for the widget tests: SQLite's isolate does not complete inside the widget
/// tester's fake clock, while these futures and streams do. Entries are newest first.
final class InMemoryHistoryStore implements HistoryStore {
  final List<HistoryEntryEntity> entries;
  final Map<int, HistoryDetail> details;
  final List<StreamController<List<HistoryEntryEntity>>> _listeners = [];
  int clears = 0;

  InMemoryHistoryStore({List<HistoryEntryEntity>? entries, Map<int, HistoryDetail>? details})
      : entries = entries ?? [],
        details = details ?? {};

  void emit() {
    for (final listener in _listeners) {
      listener.add(List.of(entries));
    }
  }

  @override
  Stream<List<HistoryEntryEntity>> watchAll() {
    late final StreamController<List<HistoryEntryEntity>> controller;
    controller = StreamController<List<HistoryEntryEntity>>(
      onListen: () {
        _listeners.add(controller);
        controller.add(List.of(entries));
      },
      onCancel: () => _listeners.remove(controller),
    );
    return controller.stream;
  }

  @override
  Stream<List<HistoryEntryEntity>> watchRecent() => watchAll();

  @override
  Future<Set<int>> searchStored(String query) async {
    final needle = HistorySearch.normalise(query);
    if (needle.isEmpty) return const {};
    return {
      for (final e in entries)
        if (_text(e).contains(needle)) e.id,
    };
  }

  String _text(HistoryEntryEntity entry) {
    final detail = details[entry.id];
    return HistorySearch.searchText(
      method: entry.method,
      url: entry.url,
      requestName: entry.meta?.requestName,
      statusCode: entry.statusCode,
      requestBody: detail?.request.body.rawText,
      responseBody: detail?.responseText,
    );
  }

  @override
  Future<HistoryDetail?> detailOf(int historyId) async => details[historyId];

  @override
  Future<void> applyRetention() async {}

  @override
  Future<void> clear() async {
    clears++;
    entries.clear();
    details.clear();
    emit();
  }

  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {}

  @override
  Future<void> recordCapture({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required HistoryCapture capture,
  }) async {}
}
