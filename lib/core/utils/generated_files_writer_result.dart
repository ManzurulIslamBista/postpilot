/// What [writeFilesToFolder] did with each file, so a screen can say so instead
/// of reporting one number.
final class WriteFilesResult {
  /// Files now on disk with the generated content (new ones and replaced ones),
  /// as the relative paths they were given.
  final List<String> written;

  /// The part of [written] that replaced a file that was already there.
  final List<String> overwritten;

  /// Files left untouched because they already existed and were not to be replaced.
  final List<String> skipped;

  const WriteFilesResult({this.written = const [], this.overwritten = const [], this.skipped = const []});

  /// Files that did not exist before.
  int get createdCount => written.length - overwritten.length;
}
