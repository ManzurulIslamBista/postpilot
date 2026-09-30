import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/api_response_entity.dart';
import '../../domain/entities/response_example_entity.dart';
import '../../domain/repositories/response_example_repository.dart';

final class ResponseExamplesViewModel with ChangeNotifier {
  final ResponseExampleRepository _repository;

  ResponseExamplesViewModel(this._repository);

  List<ResponseExampleEntity> examples = [];
  int? _requestId;
  StreamSubscription<List<ResponseExampleEntity>>? _subscription;

  void watch(int requestId) {
    if (_requestId == requestId) return;
    _requestId = requestId;
    _subscription?.cancel();
    examples = [];
    _subscription = _repository.watchByRequest(requestId).listen((value) {
      examples = value;
      notifyListeners();
    });
  }

  /// [body] is the response body as text, decoded the way the viewer shows it;
  /// only text bodies can be stored, the examples table has no binary column.
  Future<void> saveExample({required String name, required ApiResponseEntity response, required String body}) async {
    final requestId = _requestId;
    if (requestId == null) return;
    await _repository.add(ResponseExampleEntity(
      id: 0,
      requestId: requestId,
      name: name,
      statusCode: response.statusCode,
      headers: response.headers,
      body: body,
      savedAt: DateTime.now(),
    ));
  }

  Future<void> delete(int id) => _repository.delete(id);

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
