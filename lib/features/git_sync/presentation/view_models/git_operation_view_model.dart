import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/git_link.dart';
import '../../domain/entities/git_sync_exceptions.dart';
import '../../domain/repositories/git_credentials_store.dart';
import '../../domain/usecases/git_save_token_usecase.dart';

typedef UriOpener = Future<bool> Function(Uri uri);

Future<bool> _openInBrowser(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

final _tokenLike = RegExp(r'\b(?:gh[pousr]_|github_pat_)\w+');

/// A domain message trimmed and with anything shaped like a GitHub token replaced, so it is safe to show.
String _shown(String message) => message.trim().replaceAll(_tokenLike, '…');

/// [_shown] as a finished sentence, ready to have a next step appended.
String _sentence(String message) {
  final text = _shown(message);
  return RegExp(r'[.!?]$').hasMatch(text) ? text : '$text.';
}

bool _hasText(String message) => message.trim().isNotEmpty;

/// Plain-language text for any failure of a Git operation. The host and sync messages are written for people and carry
/// the specifics (when a rate limit resets, an SSO instruction, what was not found), so they are kept and given a next
/// step where one helps; anything unknown gets a generic line, and nothing shaped like a token is ever shown.
String friendlyGitError(Object error) => switch (error) {
      GitMissingTokenException() => 'Save a GitHub token first: paste one into the token field, then try again.',
      GitAuthException(:final message) when _hasText(message) =>
        '${_sentence(message)} It may have expired or lack access — update it under Settings.',
      GitAuthException() =>
        'GitHub rejected your token — it may have expired or lack access. Update it under Settings.',
      GitNotFastForwardException() => 'Someone pushed since you last pulled. Pull first, then push again.',
      GitRateLimitException(:final message) when _hasText(message) => _sentence(message),
      GitRateLimitException() => 'GitHub is limiting requests right now. Wait a few minutes and try again.',
      GitNotFoundException(:final message) when _hasText(message) => _sentence(message),
      GitNotFoundException() =>
        "GitHub couldn't find that repository. Check its name, and make sure your token can access it.",
      GitReadOnlyException() =>
        'You only have read access to this repository, so you cannot push. Ask an owner for write access.',
      GitNothingToCommitException() => 'There is nothing to commit — no local changes since the last sync.',
      GitPathOccupiedException(:final message) => _shown(message),
      GitUncommittedChangesException() =>
        'You have local changes that are not pushed yet. Push or discard them first, then try again.',
      GitSyncException(:final message) when _hasText(message) => _shown(message),
      GitHostException(:final message) when _hasText(message) => _shown(message),
      _ => 'Something went wrong — please try again.',
    };

abstract class GitOperationViewModel with ChangeNotifier {
  static const defaultBranch = 'main';
  static const _repositoryHint = 'Enter the repository as owner/repo or paste its GitHub URL.';

  final GitCredentialsStore _credentials;
  final UseCase<String, GitTokenParams> _saveTokenUseCase;
  final UriOpener _openUri;

  GitOperationViewModel({
    required this._credentials,
    required this._saveTokenUseCase,
    UriOpener? openUri,
  }) : _openUri = openUri ?? _openInBrowser;

  int _busyCount = 0;
  int _closeGuards = 0;
  bool _disposed = false;

  String? busyLabel;

  /// Friendly text of the last failed action; cleared when the next one starts.
  String? errorMessage;

  /// Confirmation of the last successful action; cleared when the next one starts.
  String? infoMessage;

  /// A token is stored on this device (its value is never exposed).
  bool hasToken = false;

  /// GitHub login the token was verified against after the last [saveToken].
  String? verifiedLogin;

  bool get isBusy => _busyCount > 0;

  /// The dialog may be dismissed. False while a change is being written (clone, commit, pull, ...): closing then would
  /// not stop it, and its result or error would be lost. Loads and refreshes do not hold the dialog open.
  bool get canClose => _closeGuards == 0;

  /// Null for a valid or still empty input, so a field only complains once something wrong was typed.
  static String? repositoryError(String input) =>
      input.trim().isEmpty || RepoRef.parse(input) != null ? null : _repositoryHint;

  /// Runs [action] behind the busy indicator and turns any failure into [errorMessage]; true when it completed.
  /// An [exclusive] action is refused while anything else is running; read-only list loads are not. An action that
  /// [guardsClose] writes something, so [canClose] is false until it has finished and reported.
  @protected
  Future<bool> run(
    String label,
    Future<void> Function() action, {
    bool exclusive = true,
    bool guardsClose = false,
  }) async {
    if (exclusive && isBusy) return false;
    if (_busyCount == 0) busyLabel = label;
    _busyCount++;
    if (guardsClose) _closeGuards++;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (error, stackTrace) {
      handleError(error, stackTrace);
      return false;
    } finally {
      _busyCount--;
      if (guardsClose) _closeGuards--;
      if (_busyCount == 0) busyLabel = null;
      notifyListeners();
    }
  }

  @protected
  void handleError(Object error, [StackTrace? stackTrace]) {
    if (kDebugMode && error is! GitSyncException && error is! GitHostException) {
      debugPrint('Git sync failed unexpectedly: $error\n$stackTrace');
    }
    errorMessage = friendlyGitError(error);
  }

  @protected
  RepoRef? parseRepositoryOrReport(String input) {
    final repo = RepoRef.parse(input);
    if (repo == null) reportError(_repositoryHint);
    return repo;
  }

  @protected
  Future<void> loadTokenState() async {
    try {
      hasToken = (await _credentials.readToken(GitProvider.github))?.isNotEmpty ?? false;
    } catch (_) {
      // Secure storage can be unreadable (blocked on some browsers); connecting reports the real problem.
      hasToken = false;
    }
  }

  @protected
  Future<void> onTokenSaved() async {}

  Future<bool> saveToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      reportError('Paste your GitHub token first.');
      return Future.value(false);
    }
    return run('Verifying token…', () async {
      try {
        verifiedLogin = await _saveTokenUseCase(GitTokenParams(provider: GitProvider.github, token: trimmed));
        hasToken = true;
      } catch (_) {
        // A rejected token is removed again or the previous one restored, so what is saved has to be read back.
        verifiedLogin = null;
        await loadTokenState();
        rethrow;
      }
      await onTokenSaved();
    });
  }

  void reportError(String message) {
    errorMessage = message;
    infoMessage = null;
    notifyListeners();
  }

  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await _openUri(uri);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened) reportError("Couldn't open your browser. Open $url yourself instead.");
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
