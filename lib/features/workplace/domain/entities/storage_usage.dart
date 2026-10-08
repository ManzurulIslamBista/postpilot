/// How much of a capped store a workspace file takes, so the person can be told before a save is refused.
final class StorageUsage {
  final int usedBytes;
  final int limitBytes;

  const StorageUsage({required this.usedBytes, required this.limitBytes});

  /// From this share of the cap on, the workspace is "close to the limit" and the UI says so.
  static const warnFraction = 0.75;

  double get fraction => limitBytes <= 0 ? 0 : usedBytes / limitBytes;

  bool get isNearLimit => fraction >= warnFraction;

  /// "3.4 MB of 4 MB".
  String get label => '${_megabytes(usedBytes)} of ${_megabytes(limitBytes)}';

  static String _megabytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb >= 10 || mb == mb.roundToDouble() ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
  }

  @override
  bool operator ==(Object other) => other is StorageUsage && other.usedBytes == usedBytes && other.limitBytes == limitBytes;

  @override
  int get hashCode => Object.hash(usedBytes, limitBytes);
}
