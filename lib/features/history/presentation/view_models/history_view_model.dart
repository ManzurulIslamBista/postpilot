import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/enums/http_method.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../../domain/repositories/history_repository.dart';

final class HistoryViewModel with ChangeNotifier {
  final HistoryRepository _repository;

  HistoryViewModel(this._repository) {
    _sub = _repository.watchRecent().listen((value) {
      entries = value;
      notifyListeners();
    });
  }

  List<HistoryEntryEntity> entries = [];
  late final StreamSubscription<List<HistoryEntryEntity>> _sub;

  Future<void> clear() => _repository.clear();

  /// Creates a new request in [collectionId] pre-filled with [entry]'s
  /// method and URL, and returns its id so it can be opened in the request
  /// builder. History only records the method, URL, and response outcome of
  /// a past send — not the original request's headers or body — so this
  /// can't restore those.
  Future<int> openInBuilder(HistoryEntryEntity entry, {required int collectionId}) async {
    final requestRepository = locator<RequestRepository>();
    final id = await requestRepository.createRequest(collectionId: collectionId, name: '${entry.method} ${entry.url}');
    final created = await requestRepository.findById(id);
    if (created != null) {
      await requestRepository.saveRequest(created.copyWith(method: HttpMethod.fromString(entry.method), url: entry.url));
    }
    return id;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
