// Pure Dart.

/// How one collection is monitored: run it again and again while the app is open.
final class MonitorConfig {
  static const minMinutes = 1;
  static const maxMinutes = 1440;
  static const defaultMinutes = 15;

  final bool enabled;

  /// Minutes between the start of one run and the start of the next.
  final int everyMinutes;

  /// The environment to run against; null follows the active one at the time of each run.
  final String? environment;

  const MonitorConfig({this.enabled = false, this.everyMinutes = defaultMinutes, this.environment});

  Duration get interval => Duration(minutes: everyMinutes.clamp(minMinutes, maxMinutes));

  /// Why [minutes] cannot be an interval; null when it can.
  static String? intervalError(String text) {
    final n = int.tryParse(text.trim());
    if (n == null || n < minMinutes || n > maxMinutes) return 'Enter a whole number of minutes from $minMinutes to $maxMinutes.';
    return null;
  }

  MonitorConfig copyWith({bool? enabled, int? everyMinutes, Object? environment = _keep}) => MonitorConfig(
        enabled: enabled ?? this.enabled,
        everyMinutes: everyMinutes ?? this.everyMinutes,
        environment: identical(environment, _keep) ? this.environment : environment as String?,
      );

  static const Object _keep = Object();

  Map<String, Object?> toJson() => {'enabled': enabled, 'every': everyMinutes, if (environment != null) 'env': environment};

  /// Tolerant of whatever the settings store holds: a bad field takes its default.
  factory MonitorConfig.fromJson(Map<String, Object?> json) {
    final every = json['every'];
    return MonitorConfig(
      enabled: json['enabled'] == true,
      everyMinutes: every is int && every >= minMinutes && every <= maxMinutes ? every : defaultMinutes,
      environment: json['env'] is String && (json['env'] as String).isNotEmpty ? json['env'] as String : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MonitorConfig && other.enabled == enabled && other.everyMinutes == everyMinutes && other.environment == environment;

  @override
  int get hashCode => Object.hash(enabled, everyMinutes, environment);
}

/// Where a monitored collection stands.
enum MonitorState {
  /// Not monitored.
  off,

  /// Monitored, waiting for the next run.
  waiting,
  running,
  passing,
  failing,

  /// The last run could not be made (the collection was not readable, nothing could be sent).
  error,
}

final class MonitorStatus {
  final MonitorState state;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;

  /// Failed requests of the last run.
  final int failed;

  /// Requests the last run left out because they change data and the environment is production.
  final int skippedByLock;

  /// The last run sent nothing: every request was left out.
  final bool ranNothing;
  final String? error;

  const MonitorStatus({
    this.state = MonitorState.off,
    this.lastRunAt,
    this.nextRunAt,
    this.failed = 0,
    this.skippedByLock = 0,
    this.ranNothing = false,
    this.error,
  });

  bool get isFailing => state == MonitorState.failing;
}

/// A run that went from passing (or unknown) to failing, for the banner.
final class MonitorAlert {
  final int collectionId;
  final String collectionName;
  final int failed;
  final DateTime at;

  const MonitorAlert({required this.collectionId, required this.collectionName, required this.failed, required this.at});
}
