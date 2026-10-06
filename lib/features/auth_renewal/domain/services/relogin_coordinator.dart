// Pure Dart (no Flutter).
import 'dart:async';

/// How one run of the login request ended.
final class ReloginLogin {
  /// The login request answered 2xx and (where it has extractors) saved what they extract.
  final bool ok;

  /// Why it did not work, masked, in a few words; null when [ok].
  final String? failure;

  /// This caller did not run the login: another request had just done it, or was doing it, and this one
  /// shares the result.
  final bool shared;

  /// No login was started because a recent one failed or did not help; [failure] says why.
  final bool skipped;

  const ReloginLogin.ok({this.shared = false})
      : ok = true,
        failure = null,
        skipped = false;

  const ReloginLogin.failed(String this.failure, {this.shared = false})
      : ok = false,
        skipped = false;

  const ReloginLogin.skipped(String this.failure)
      : ok = false,
        shared = true,
        skipped = true;

  ReloginLogin asShared() => ok ? const ReloginLogin.ok(shared: true) : ReloginLogin.failed(failure!, shared: true);
}

/// Decides when the login request really runs, so a burst of 401s does not turn into a burst of logins:
///  * requests that fail together wait for one login and each retry afterwards;
///  * a request that was sent before the last login finished does not log in again, its 401 came from the
///    token that login replaced;
///  * after a login failed, no new one is started for [cooldown]. Wrong credentials sent again and again
///    can lock the account, and nothing would have changed anyway.
final class ReloginCoordinator {
  final DateTime Function() _now;
  final Duration cooldown;

  final Map<String, Future<ReloginLogin>> _running = {};
  final Map<String, DateTime> _lastSuccess = {};
  final Map<String, ({DateTime at, String why})> _lastFailure = {};

  ReloginCoordinator({DateTime Function()? now, this.cooldown = const Duration(seconds: 60)}) : _now = now ?? DateTime.now;

  /// [key] identifies the login (the collection and the request it runs). [requestSentAt] is when the
  /// request that failed went out. [login] runs the login request; it must not throw.
  Future<ReloginLogin> run(String key, DateTime requestSentAt, Future<ReloginLogin> Function() login) async {
    final succeeded = _lastSuccess[key];
    if (succeeded != null && requestSentAt.isBefore(succeeded)) return const ReloginLogin.ok(shared: true);

    final running = _running[key];
    if (running != null) return (await running).asShared();

    final failed = _lastFailure[key];
    if (failed != null && _now().difference(failed.at) < cooldown) {
      return ReloginLogin.skipped('${failed.why}; not tried again for ${cooldown.inSeconds} s');
    }

    final flight = () async {
      try {
        final result = await login();
        if (result.ok) {
          _lastSuccess[key] = _now();
          _lastFailure.remove(key);
        } else {
          _lastFailure[key] = (at: _now(), why: result.failure ?? 'it failed');
        }
        return result;
      } finally {
        _running.remove(key);
      }
    }();
    _running[key] = flight;
    return flight;
  }

  /// The request that was sent again after a login was rejected a second time (HTTP 403 for a user who may
  /// not do that, a token that does not fit): another login would not help, so none is started for
  /// [cooldown], as after a failed login.
  void markIneffective(String key, String why) {
    _lastSuccess.remove(key);
    _lastFailure[key] = (at: _now(), why: why);
  }

  /// Forgets the failure of [key], so the next 401 may try again at once (a person fixed the login).
  void reset(String key) {
    _lastFailure.remove(key);
    _lastSuccess.remove(key);
  }
}
