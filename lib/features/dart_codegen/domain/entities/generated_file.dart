/// One file a generator produced: a path relative to the folder the user picks
/// (`lib/models/user.dart`) and its full text.
final class GeneratedFile {
  final String path;
  final String content;

  /// Shared by every generated feature and likely to be the project's own already
  /// (`lib/core/network/api_client.dart`, the UseCase base class). A writer leaves an
  /// existing copy alone and says so, instead of replacing the user's version.
  final bool shared;

  const GeneratedFile(this.path, this.content, {this.shared = false});

  String get name => path.split('/').last;
}
