/// What History keeps, as set in Settings > History.
final class HistoryLimits {
  static const defaultMaxEntries = 1000;
  static const minMaxEntries = 10;
  static const maxMaxEntries = 5000;

  /// The longest request or response text kept with an entry.
  static const defaultMaxBodyBytes = 256 * 1024;
  static const minMaxBodyBytes = 1024;
  static const maxMaxBodyBytes = 4 * 1024 * 1024;

  /// Request and response bodies are stored with each entry. Off: only the one-line summary is.
  final bool keepBodies;

  /// The newest this many entries are kept; older ones are removed as new ones are written.
  final int maxEntries;

  /// Entries older than this many days are removed too; null keeps them until [maxEntries] pushes them out.
  final int? retentionDays;
  final int maxBodyBytes;

  const HistoryLimits({
    this.keepBodies = true,
    this.maxEntries = defaultMaxEntries,
    this.retentionDays,
    this.maxBodyBytes = defaultMaxBodyBytes,
  });

  @override
  bool operator ==(Object other) =>
      other is HistoryLimits &&
      other.keepBodies == keepBodies &&
      other.maxEntries == maxEntries &&
      other.retentionDays == retentionDays &&
      other.maxBodyBytes == maxBodyBytes;

  @override
  int get hashCode => Object.hash(keepBodies, maxEntries, retentionDays, maxBodyBytes);
}

/// Where History reads its limits from. Asked on every write, so a change in Settings applies to the next send.
abstract interface class HistoryPolicy {
  Future<HistoryLimits> limits();
}

/// A policy that never changes: the defaults, or whatever it is given.
final class FixedHistoryPolicy implements HistoryPolicy {
  final HistoryLimits _limits;
  const FixedHistoryPolicy([this._limits = const HistoryLimits()]);

  @override
  Future<HistoryLimits> limits() async => _limits;
}
