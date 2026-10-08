// Pure Dart (no Flutter): the ledger of the app and the cleanup of the command line run through the same code.
import '../../../../core/errors/app_exception.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../entities/cleanup_entry.dart';

/// The request that undoes an entry, or why there is none.
final class CleanupPrepared {
  final CleanupEntry entry;
  final ApiRequestEntity? request;
  final String? failure;

  const CleanupPrepared.ready(this.entry, ApiRequestEntity this.request) : failure = null;
  const CleanupPrepared.failed(this.entry, String this.failure) : request = null;
}

/// How the delete of one entry went: [CleanupState.deleted] or [CleanupState.failed] with the [reason].
final class CleanupResult {
  final CleanupEntry entry;
  final CleanupState state;
  final String? reason;

  const CleanupResult(this.entry, this.state, [this.reason]);

  bool get ok => state == CleanupState.deleted;
}

/// Sends the request that undoes an entry. The app's goes through the normal send pipeline; the command line's through
/// its own runner. Both must leave the production lock and the unresolved-variable check in force.
abstract interface class CleanupSender {
  /// The request that undoes [entry]; or why it cannot be sent at all (the environment changed, the undo request was
  /// renamed). Nothing is sent here.
  Future<CleanupPrepared> prepare(CleanupEntry entry);

  /// Sends it and says how it went. The server refusing is a [CleanupState.failed] result, not an exception.
  Future<CleanupResult> send(CleanupPrepared prepared);
}

/// Asked once with every request about to go out; false stops the lot before anything is sent (the person said no to
/// the production warning).
typedef CleanupGate = Future<bool> Function(List<ApiRequestEntity> requests);

/// What a cleanup did.
final class CleanupRun {
  /// One result per entry that was tried, in the order they were tried.
  final List<CleanupResult> results;

  /// The gate said no: nothing was sent and no entry changed.
  final bool declined;

  const CleanupRun(this.results, {this.declined = false});

  int get deleted => results.where((r) => r.ok).length;
  int get failed => results.where((r) => !r.ok).length;
}

abstract final class CleanupExecutor {
  /// Deletes what [entries] created, the newest first, so what was made last (and may depend on what came before) goes
  /// first. Every entry is tried: one that fails is reported with its reason and the rest still go. Entries that are
  /// already deleted or skipped are left alone. [gate] sees every request that is about to be sent, once, before the
  /// first one goes. [onResult] hears each result as it comes.
  static Future<CleanupRun> run(
    Iterable<CleanupEntry> entries,
    CleanupSender sender, {
    CleanupGate? gate,
    void Function(CleanupResult result)? onResult,
  }) async {
    final order = [for (final e in entries) if (e.canDelete) e]..sort((a, b) => b.id.compareTo(a.id));
    if (order.isEmpty) return const CleanupRun([]);

    final prepared = <CleanupPrepared>[];
    for (final entry in order) {
      try {
        prepared.add(await sender.prepare(entry));
      } catch (error) {
        prepared.add(CleanupPrepared.failed(entry, describe(error)));
      }
    }

    final requests = [for (final p in prepared) ?p.request];
    if (gate != null && requests.isNotEmpty && !await gate(requests)) return const CleanupRun([], declined: true);

    final results = <CleanupResult>[];
    for (final item in prepared) {
      CleanupResult result;
      if (item.request == null) {
        result = CleanupResult(item.entry, CleanupState.failed, item.failure ?? 'The undo request could not be built.');
      } else {
        try {
          result = await sender.send(item);
        } catch (error) {
          result = CleanupResult(item.entry, CleanupState.failed, describe(error));
        }
      }
      results.add(result);
      onResult?.call(result);
    }
    return CleanupRun(results);
  }

  /// A failure in words for a list, with anything secret taken out.
  static String describe(Object error) {
    final text = error is NetworkException ? error.summary ?? error.message : error.toString();
    return SecretMasker.maskMessage(text);
  }
}
