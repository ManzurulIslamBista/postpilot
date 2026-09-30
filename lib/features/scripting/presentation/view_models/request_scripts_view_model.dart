import 'package:flutter/foundation.dart';
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../data/models/scripts_json_codec.dart';
import '../../domain/entities/assertion_entity.dart';
import '../../domain/entities/extractor_entity.dart';

/// Backs the Tests tab: holds the editable assertion/extractor lists for one
/// request and persists every change immediately.
final class RequestScriptsViewModel with ChangeNotifier {
  final RequestScriptsRepository _repository;

  RequestScriptsViewModel(this._repository);

  int? _requestId;
  List<AssertionEntity> assertions = [];
  List<ExtractorEntity> extractors = [];
  bool isLoading = false;

  Future<void> load(int requestId) async {
    _requestId = requestId;
    isLoading = true;
    notifyListeners();

    final scripts = await _repository.get(requestId);
    if (_requestId != requestId) return; // a newer load() superseded this one

    assertions = ScriptsJsonCodec.decodeAssertions(scripts?.assertionsJson ?? '[]');
    extractors = ScriptsJsonCodec.decodeExtractors(scripts?.extractorsJson ?? '[]');
    isLoading = false;
    notifyListeners();
  }

  void updateAssertions(List<AssertionEntity> items) {
    assertions = items;
    notifyListeners();
    _save();
  }

  void updateExtractors(List<ExtractorEntity> items) {
    extractors = items;
    notifyListeners();
    _save();
  }

  void _save() {
    final requestId = _requestId;
    if (requestId == null) return;
    _repository.save(RequestScriptsEntity(
      requestId: requestId,
      assertionsJson: ScriptsJsonCodec.encodeAssertions(assertions),
      extractorsJson: ScriptsJsonCodec.encodeExtractors(extractors),
    ));
  }
}
