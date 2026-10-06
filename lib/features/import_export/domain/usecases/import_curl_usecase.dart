import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/services/importers/curl_parser.dart';

final class ImportCurlParams {
  final int collectionId;
  final int? folderId;
  final String curlCommand;
  const ImportCurlParams({required this.collectionId, required this.folderId, required this.curlCommand});
}

/// Turns one pasted `curl ...` command into a new saved request.
final class ImportCurlUseCase implements UseCase<int, ImportCurlParams> {
  final RequestRepository _requestRepository;
  const ImportCurlUseCase(this._requestRepository);

  @override
  Future<int> call(ImportCurlParams params) async {
    final parsed = CurlParser.parse(params.curlCommand);
    if (parsed == null) throw const ImportException('Could not find a URL in that cURL command.');

    final name = Uri.tryParse(parsed.url)?.path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? parsed.url;
    final requestId = await _requestRepository.createRequest(
      collectionId: params.collectionId,
      folderId: params.folderId,
      name: name.isEmpty ? parsed.url : name,
    );

    await _requestRepository.saveRequest(ApiRequestEntity(
      id: requestId,
      collectionId: params.collectionId,
      folderId: params.folderId,
      name: name.isEmpty ? parsed.url : name,
      method: parsed.method,
      url: parsed.url,
      headers: parsed.headers,
      queryParams: const [],
      body: parsed.requestBody,
      auth: parsed.auth,
    ));

    return requestId;
  }
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
