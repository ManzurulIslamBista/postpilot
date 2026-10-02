/// One file a generator produced: a path relative to the folder the user picks
/// (`lib/models/user.dart`) and its full text.
final class GeneratedFile {
  final String path;
  final String content;
  const GeneratedFile(this.path, this.content);

  String get name => path.split('/').last;
}
