import '../../../../core/utils/variable_resolver.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../entities/history_entry_entity.dart';
import '../entities/history_snapshot.dart';
import 'history_repository.dart';

/// What a send hands to History beyond the summary line: the request it was
/// sent from (as saved, with `{{variables}}`) and the answer, so the entry can
/// be searched, looked at, edited and sent again. Nothing here is stored as
/// it is: the store masks credentials, cuts the texts and keeps only text.
final class HistoryCapture {
  final ApiRequestEntity request;

  /// The response body as it arrived; empty for a send that failed.
  final List<int> responseBytes;
  final String? responseContentType;
  final String statusMessage;

  /// The response was cut off at the response size limit of the settings.
  final bool responseTruncated;

  /// Why there was no response, for a send that failed.
  final String? error;

  /// The variables the request was resolved with: their secret values are
  /// hidden from the stored texts in case a server echoes them back. Never stored.
  final VariableResolver? resolver;

  const HistoryCapture({
    required this.request,
    this.responseBytes = const [],
    this.responseContentType,
    this.statusMessage = '',
    this.responseTruncated = false,
    this.error,
    this.resolver,
  });
}

/// Names and secrets around a request that History cannot see itself.
final class HistoryContext {
  final String? collectionName;
  final String? environmentName;

  /// Variables the user marked secret in an environment or the globals.
  final Set<String> flaggedSecretKeys;

  /// Literal credentials in play that no variable holds (the collection's own auth).
  final List<String> secretValues;

  const HistoryContext({
    this.collectionName,
    this.environmentName,
    this.flaggedSecretKeys = const {},
    this.secretValues = const [],
  });
}

abstract interface class HistoryContextSource {
  Future<HistoryContext> of(ApiRequestEntity request);
}

/// A [HistoryRepository] that keeps more than the summary line. Kept apart from
/// it so that code (and tests) written against the narrow interface go on working.
abstract interface class HistoryStore implements HistoryRepository {
  /// Every entry kept, newest first, with what [HistoryEntryEntity.meta] says.
  Stream<List<HistoryEntryEntity>> watchAll();

  /// [record] plus the request snapshot and the response text of [capture],
  /// unless "Keep request/response bodies in history" is off.
  Future<void> recordCapture({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required HistoryCapture capture,
  });

  /// The ids of entries whose stored text (request, response, name, ...) holds [query].
  Future<Set<int>> searchStored(String query);

  /// The snapshot and answer kept for [historyId]; null when there are none.
  Future<HistoryDetail?> detailOf(int historyId);

  /// Removes what the current limits no longer allow (fewer entries kept, shorter retention).
  Future<void> applyRetention();
}
