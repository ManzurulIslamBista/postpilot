/// "When a request of this collection (or folder) comes back 401 or 403, run the request [request] first,
/// then send the failed one again, once." [request] is a login request of the same collection whose
/// extractors fill the variable the other requests authenticate with.
///
/// Kept inside the auth JSON of the level that sets it (`RequestAuth.relogin`, key `relogin`), so it
/// travels with the collection auth through the database, a backup, a workspace file and Git.
/// It holds no secret: only the name of a request and the statuses.
final class ReloginConfig {
  /// The statuses that start a re-login when none is chosen.
  static const defaultStatuses = {401, 403};

  /// The login request: its name (`Login`), or with the folders above it (`Auth/Login`), the same
  /// selector `postpilot run --request` takes. A name is kept instead of an id because ids differ
  /// between machines, backups and Git checkouts.
  final String request;

  /// The response statuses that trigger it.
  final Set<int> statuses;

  const ReloginConfig({required this.request, this.statuses = defaultStatuses});

  /// A config that names no request does nothing; it is kept only while the user is still choosing.
  bool get isActive => request.trim().isNotEmpty && statuses.isNotEmpty;

  bool triggersOn(int statusCode) => isActive && statuses.contains(statusCode);

  ReloginConfig copyWith({String? request, Set<int>? statuses}) =>
      ReloginConfig(request: request ?? this.request, statuses: statuses ?? this.statuses);

  /// `statuses` is written only when it is not the default, so the common config stays one key.
  Map<String, Object?> toJson() => {
        'request': request,
        if (!_sameStatuses(statuses, defaultStatuses)) 'statuses': (statuses.toList()..sort()),
      };

  /// Null for anything that is not a config (absent, not a map, no request name). Tolerant: a damaged
  /// value must not break reading the auth it sits in.
  static ReloginConfig? fromJson(Object? value) {
    if (value is! Map) return null;
    final request = value['request'];
    if (request is! String || request.trim().isEmpty) return null;
    final raw = value['statuses'];
    final statuses = raw is List ? {for (final s in raw) if (s is int && s >= 100 && s <= 599) s} : <int>{};
    return ReloginConfig(request: request.trim(), statuses: raw is List ? statuses : defaultStatuses);
  }

  @override
  bool operator ==(Object other) =>
      other is ReloginConfig && other.request == request && _sameStatuses(other.statuses, statuses);

  @override
  int get hashCode => Object.hash(request, Object.hashAllUnordered(statuses));

  static bool _sameStatuses(Set<int> a, Set<int> b) => a.length == b.length && a.containsAll(b);
}
