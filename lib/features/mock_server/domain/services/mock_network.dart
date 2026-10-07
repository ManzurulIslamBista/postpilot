import 'dart:math';

/// Ways an answer can arrive broken, besides being cut off by the network.
enum NetworkCorruption {
  truncatedJson('Truncated JSON', 'The body stops half way, so it does not parse'),
  malformedJson('Broken JSON syntax', 'The body has a trailing comma: valid JavaScript, invalid JSON'),
  wrongContentType('Wrong content type', 'JSON served as text/html'),
  wrongContentLength('Wrong content length', 'Content-Length claims more bytes than arrive, then the connection closes');

  const NetworkCorruption(this.label, this.description);

  final String label;
  final String description;
}

/// What a bad network does to every request, as numbers a person can edit. One profile describes one kind of trouble (or several
/// at once); [MockNetwork] applies it. Immutable: editing a profile makes a new one.
final class NetworkProfile {
  final String id;
  final String name;
  final String description;

  /// The wait before the first byte of the answer, and how far it varies either way (a share of it).
  final int latencyMs;
  final int jitterPercent;

  /// The speed of the answer's body, in kilobit per second; 0 sends it as fast as the machine can. The body really is written in
  /// paced chunks, so a client's progress and timeouts behave as they would on that link.
  final int bandwidthKbps;

  /// Every connection is dropped before any answer.
  final bool offline;

  /// Share of the requests whose connection is dropped, whose body is cut off half way (the connection is then dropped), and that
  /// never get an answer.
  final int resetPercent;
  final int truncatePercent;
  final int timeoutPercent;

  /// Share of the requests answered with one of [errorStatuses] instead of the route's answer, with a `Retry-After` header of
  /// [retryAfterSeconds] when that is above 0.
  final int errorPercent;
  final List<int> errorStatuses;
  final int retryAfterSeconds;

  /// Share of the requests whose answer is broken in one of [corruptModes].
  final int corruptPercent;
  final List<NetworkCorruption> corruptModes;

  /// The connection works for [upSeconds], then drops for [downSeconds], over and over (both above 0).
  final int upSeconds;
  final int downSeconds;

  const NetworkProfile({
    required this.id,
    required this.name,
    this.description = '',
    this.latencyMs = 0,
    this.jitterPercent = 0,
    this.bandwidthKbps = 0,
    this.offline = false,
    this.resetPercent = 0,
    this.truncatePercent = 0,
    this.timeoutPercent = 0,
    this.errorPercent = 0,
    this.errorStatuses = const [500, 502, 503],
    this.retryAfterSeconds = 0,
    this.corruptPercent = 0,
    this.corruptModes = NetworkCorruption.values,
    this.upSeconds = 0,
    this.downSeconds = 0,
  });

  bool get isFlapping => upSeconds > 0 && downSeconds > 0;

  /// Nothing to apply: the request is answered as it would be without a profile.
  bool get isIdle =>
      latencyMs <= 0 &&
      bandwidthKbps <= 0 &&
      !offline &&
      !isFlapping &&
      resetPercent <= 0 &&
      truncatePercent <= 0 &&
      timeoutPercent <= 0 &&
      (errorPercent <= 0 || errorStatuses.isEmpty) &&
      (corruptPercent <= 0 || corruptModes.isEmpty);

  /// The numbers that are set, in a line: `first byte 300 ms ±25%, 750 kbit/s`.
  String get summary {
    final parts = <String>[
      if (offline) 'every connection dropped',
      if (latencyMs > 0) 'first byte ${latencyMs >= 1000 ? '${(latencyMs / 1000).toStringAsFixed(latencyMs % 1000 == 0 ? 0 : 1)} s' : '$latencyMs ms'}${jitterPercent > 0 ? ' ±$jitterPercent%' : ''}',
      if (bandwidthKbps > 0) '$bandwidthKbps kbit/s',
      if (isFlapping) 'up $upSeconds s, down $downSeconds s',
      if (resetPercent > 0) '$resetPercent% dropped',
      if (truncatePercent > 0) '$truncatePercent% cut off',
      if (timeoutPercent > 0) '$timeoutPercent% never answered',
      if (errorPercent > 0 && errorStatuses.isNotEmpty) '$errorPercent% ${errorStatuses.join('/')}${retryAfterSeconds > 0 ? ' with Retry-After $retryAfterSeconds s' : ''}',
      if (corruptPercent > 0 && corruptModes.isNotEmpty) '$corruptPercent% corrupt',
    ];
    return parts.isEmpty ? 'No effect' : parts.join(', ');
  }

  NetworkProfile copyWith({
    String? id,
    String? name,
    String? description,
    int? latencyMs,
    int? jitterPercent,
    int? bandwidthKbps,
    bool? offline,
    int? resetPercent,
    int? truncatePercent,
    int? timeoutPercent,
    int? errorPercent,
    List<int>? errorStatuses,
    int? retryAfterSeconds,
    int? corruptPercent,
    List<NetworkCorruption>? corruptModes,
    int? upSeconds,
    int? downSeconds,
  }) =>
      NetworkProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        latencyMs: latencyMs ?? this.latencyMs,
        jitterPercent: jitterPercent ?? this.jitterPercent,
        bandwidthKbps: bandwidthKbps ?? this.bandwidthKbps,
        offline: offline ?? this.offline,
        resetPercent: resetPercent ?? this.resetPercent,
        truncatePercent: truncatePercent ?? this.truncatePercent,
        timeoutPercent: timeoutPercent ?? this.timeoutPercent,
        errorPercent: errorPercent ?? this.errorPercent,
        errorStatuses: errorStatuses ?? this.errorStatuses,
        retryAfterSeconds: retryAfterSeconds ?? this.retryAfterSeconds,
        corruptPercent: corruptPercent ?? this.corruptPercent,
        corruptModes: corruptModes ?? this.corruptModes,
        upSeconds: upSeconds ?? this.upSeconds,
        downSeconds: downSeconds ?? this.downSeconds,
      );
}

/// The ready-made profiles. The numbers are typical, not measured: edit them.
abstract final class NetworkProfiles {
  static const none = NetworkProfile(id: 'none', name: 'No throttling', description: 'The server answers as fast as it can.');

  static const offline = NetworkProfile(
    id: 'offline',
    name: 'Offline',
    description: 'The connection is dropped before any answer: the app sees a connection error, as with no network.',
    offline: true,
  );

  static const twoG = NetworkProfile(
    id: '2g',
    name: '2G',
    description: 'Very slow and laggy: about 50 kbit/s and a long round trip.',
    latencyMs: 800,
    jitterPercent: 30,
    bandwidthKbps: 50,
  );

  static const threeG = NetworkProfile(
    id: '3g',
    name: '3G',
    description: 'A busy mobile connection: 750 kbit/s and a 300 ms round trip.',
    latencyMs: 300,
    jitterPercent: 25,
    bandwidthKbps: 750,
  );

  static const fourG = NetworkProfile(
    id: '4g',
    name: '4G',
    description: 'A decent mobile connection: 9 Mbit/s and a 60 ms round trip.',
    latencyMs: 60,
    jitterPercent: 20,
    bandwidthKbps: 9000,
  );

  static const slowWifi = NetworkProfile(
    id: 'slow-wifi',
    name: 'Slow Wi-Fi',
    description: 'A weak signal: 2 Mbit/s, 150 ms, and the delay jumps around.',
    latencyMs: 150,
    jitterPercent: 50,
    bandwidthKbps: 2000,
  );

  static const lossy = NetworkProfile(
    id: 'lossy',
    name: 'Lossy',
    description: 'A flaky link: some connections are dropped, some answers are cut off half way.',
    latencyMs: 120,
    jitterPercent: 30,
    resetPercent: 10,
    truncatePercent: 10,
  );

  static const flapping = NetworkProfile(
    id: 'flapping',
    name: 'Flapping',
    description: 'The connection works for a while, then drops, over and over.',
    upSeconds: 10,
    downSeconds: 5,
  );

  static const highLatency = NetworkProfile(
    id: 'high-latency',
    name: 'High latency + timeouts',
    description: 'A very long round trip, and some requests are never answered at all.',
    latencyMs: 6000,
    jitterPercent: 30,
    timeoutPercent: 25,
  );

  static const serverErrors = NetworkProfile(
    id: 'server-errors',
    name: 'Server errors',
    description: 'Some requests fail with 500, 502 or 503 and a Retry-After header.',
    errorPercent: 30,
    retryAfterSeconds: 5,
  );

  static const corrupt = NetworkProfile(
    id: 'corrupt',
    name: 'Corrupt answers',
    description: 'Some answers arrive broken: cut-off or invalid JSON, a wrong content type or a wrong content length.',
    corruptPercent: 50,
  );

  static const slowFirstByte = NetworkProfile(
    id: 'slow-first-byte',
    name: 'Slow first byte',
    description: 'Nothing for 4 seconds, then the whole answer at once. A client sees a long wait for the headers.',
    latencyMs: 4000,
  );

  static const slowBody = NetworkProfile(
    id: 'slow-body',
    name: 'Slow body',
    description: 'The headers come at once, then the body trickles in at 16 kbit/s. A client sees the answer start, then stall.',
    bandwidthKbps: 16,
  );

  /// What the selector offers, after "No throttling".
  static const presets = [offline, twoG, threeG, fourG, slowWifi, lossy, flapping, highLatency, serverErrors, corrupt, slowFirstByte, slowBody];

  /// The id an edited copy of a preset gets.
  static const customId = 'custom';

  static NetworkProfile? byId(String id) => id == none.id ? none : presets.where((p) => p.id == id).firstOrNull;
}

/// What the network does to one request, decided by the profile in force.
final class NetworkDecision {
  /// A wait before the first byte of the answer.
  final Duration latency;

  /// Close the connection without an answer.
  final bool dropConnection;

  /// Never answer; the connection stays open.
  final bool hang;

  /// Answer this status instead of the route's own answer, with `Retry-After` when [retryAfterSeconds] is set.
  final int? errorStatus;
  final int? retryAfterSeconds;
  final NetworkCorruption? corruption;

  /// The speed of the body in bytes per second; 0 for no limit.
  final int bytesPerSecond;

  /// The share (0 to 1) of the body sent before the connection is dropped; null sends all of it.
  final double? truncateAt;

  /// The profile's name and what it did to this request (`3G: +312 ms, 750 kbit/s`), for the request log; null when nothing applied.
  final String? profile;
  final String? label;

  const NetworkDecision({
    this.latency = Duration.zero,
    this.dropConnection = false,
    this.hang = false,
    this.errorStatus,
    this.retryAfterSeconds,
    this.corruption,
    this.bytesPerSecond = 0,
    this.truncateAt,
    this.profile,
    this.label,
  });

  static const none = NetworkDecision();
}

/// The network profiles in force: one for the whole server and one per route, changed while it runs. A route's own profile
/// replaces the one for the whole server, so "No throttling" on a route exempts it. A flapping profile counts its cycles from the
/// moment it was set.
final class MockNetwork {
  final DateTime Function() _now;
  MockNetwork(this._now);

  NetworkProfile? global;
  final Map<String, NetworkProfile> _routes = {};
  final Map<String, DateTime> _since = {};

  static const _globalScope = 'global';

  /// Routes that have a profile of their own ("No throttling" included).
  Map<String, NetworkProfile> get routes => Map.unmodifiable(_routes);

  bool get isIdle => (global?.isIdle ?? true) && _routes.values.every((p) => p.isIdle);

  void setGlobal(NetworkProfile? profile) {
    global = profile;
    _since[_globalScope] = _now();
  }

  /// A profile for the route with this key (`GET /users/:id`); null takes it back to the whole server's.
  void setRoute(String key, NetworkProfile? profile) {
    if (profile == null) {
      _routes.remove(key);
      _since.remove('route:$key');
    } else {
      _routes[key] = profile;
      _since['route:$key'] = _now();
    }
  }

  void clear() {
    global = null;
    _routes.clear();
    _since.clear();
  }

  ({NetworkProfile? profile, String scope}) _effective(String? routeKey) {
    final own = routeKey == null ? null : _routes[routeKey];
    return own == null ? (profile: global, scope: _globalScope) : (profile: own, scope: 'route:$routeKey');
  }

  /// What to do with the next request for [routeKey] (null when no route matched). Chance is drawn from [random] in a fixed
  /// order (the jitter, one roll for dropped / never answered / cut off, then the error, then the corruption), and only for the
  /// effects the profile has, so a seeded [random] gives the same run every time.
  NetworkDecision decide(String? routeKey, Random random) {
    final (:profile, :scope) = _effective(routeKey);
    if (profile == null || profile.isIdle) return NetworkDecision.none;
    final name = profile.name;
    NetworkDecision drop(Duration latency, String what) => NetworkDecision(latency: latency, dropConnection: true, profile: name, label: '$name: $what');

    final parts = <String>[];
    if (profile.isFlapping) {
      final up = profile.upSeconds * 1000;
      final cycle = up + profile.downSeconds * 1000;
      final into = _now().difference(_since[scope] ?? _now()).inMilliseconds % cycle;
      if (into >= up) return drop(Duration.zero, 'down, connection dropped');
      parts.add('up');
    }
    if (profile.offline) return drop(Duration.zero, 'connection dropped');

    var wait = profile.latencyMs;
    if (wait > 0 && profile.jitterPercent > 0) {
      final swing = (random.nextDouble() * 2 - 1) * profile.jitterPercent / 100;
      wait = max(0, (wait * (1 + swing)).round());
    }
    final latency = Duration(milliseconds: max(0, wait));
    if (wait > 0) parts.add('+$wait ms');

    double? truncateAt;
    if (profile.resetPercent > 0 || profile.timeoutPercent > 0 || profile.truncatePercent > 0) {
      final roll = random.nextInt(100);
      var edge = profile.resetPercent;
      if (roll < edge) return drop(latency, 'connection dropped${wait > 0 ? ' after +$wait ms' : ''}');
      edge += profile.timeoutPercent;
      if (roll < edge) return NetworkDecision(hang: true, profile: name, label: '$name: no answer');
      edge += profile.truncatePercent;
      if (roll < edge) truncateAt = 0.2 + random.nextDouble() * 0.6;
    }

    int? error;
    if (truncateAt == null && profile.errorPercent > 0 && profile.errorStatuses.isNotEmpty && random.nextInt(100) < profile.errorPercent) {
      error = profile.errorStatuses[random.nextInt(profile.errorStatuses.length)];
    }
    NetworkCorruption? corruption;
    if (truncateAt == null && error == null && profile.corruptPercent > 0 && profile.corruptModes.isNotEmpty && random.nextInt(100) < profile.corruptPercent) {
      corruption = profile.corruptModes[random.nextInt(profile.corruptModes.length)];
    }

    final retryAfter = error != null && profile.retryAfterSeconds > 0 ? profile.retryAfterSeconds : null;
    if (profile.bandwidthKbps > 0) parts.add('${profile.bandwidthKbps} kbit/s');
    if (truncateAt != null) parts.add('body cut at ${(truncateAt * 100).round()}%');
    if (error != null) parts.add('error $error${retryAfter != null ? ' with Retry-After $retryAfter s' : ''}');
    if (corruption != null) parts.add(corruption.label.toLowerCase());
    return NetworkDecision(
      latency: latency,
      errorStatus: error,
      retryAfterSeconds: retryAfter,
      corruption: corruption,
      bytesPerSecond: profile.bandwidthKbps * 125,
      truncateAt: truncateAt,
      profile: name,
      label: '$name: ${parts.isEmpty ? 'passed' : parts.join(', ')}',
    );
  }
}
