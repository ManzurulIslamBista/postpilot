// Pure Dart (no Flutter): builds text, touches no file.

/// How often a scheduled run (the monitor) starts. Scheduled workflows run in UTC and GitHub starts them at most every
/// five minutes, often a little late; the presets avoid the top of the hour, when GitHub is busiest.
enum CiSchedulePreset {
  none('No schedule', null),
  hourly('Every hour', '17 * * * *'),
  daily('Every day at 06:17 UTC', '17 6 * * *'),
  weekdays('Weekdays at 06:17 UTC', '17 6 * * 1-5'),
  custom('Custom cron…', null);

  final String label;
  final String? cron;
  const CiSchedulePreset(this.label, this.cron);
}

/// A secret variable the workflow must be given: PostPilot reads `POSTPILOT_VAR_<variable>`, and the job takes its
/// value from the repository secret [secretName]. Names only, never a value.
final class CiSecret {
  /// The variable as PostPilot knows it (`odooApiKey`).
  final String variable;

  /// The name of the secret to create in the CI system (`ODOO_API_KEY`).
  final String secretName;

  const CiSecret(this.variable, this.secretName);

  /// The environment variable the command line reads it from.
  String get processVariable => 'POSTPILOT_VAR_$variable';

  @override
  bool operator ==(Object other) => other is CiSecret && other.variable == variable && other.secretName == secretName;

  @override
  int get hashCode => Object.hash(variable, secretName);
}

/// Everything the generated CI setup depends on.
final class CiOptions {
  /// The environment the run uses (`--env`); null runs without one.
  final String? environment;

  /// Only this collection (`--collection`); null runs every collection.
  final String? collection;

  /// The workspace file as the repository holds it: relative to the repository root, with forward slashes.
  final String workspacePath;
  final CiSchedulePreset schedule;

  /// The cron expression when [schedule] is [CiSchedulePreset.custom].
  final String customCron;

  /// `--fail-on-skip`: a skipped request fails the run.
  final bool failOnSkip;

  /// `--allow-production`: the run may send data-changing requests to production. Off unless chosen on purpose.
  final bool allowProduction;

  /// `--bail`: stop at the first failure.
  final bool bail;

  /// The branch, tag or commit of PostPilot to run.
  final String postpilotRef;

  /// On a failed scheduled run, open one GitHub issue (or comment on the open one).
  final bool openIssueOnFailure;
  final List<CiSecret> secrets;

  const CiOptions({
    this.environment,
    this.collection,
    this.workspacePath = 'workspace.json',
    this.schedule = CiSchedulePreset.none,
    this.customCron = '',
    this.failOnSkip = false,
    this.allowProduction = false,
    this.bail = false,
    this.postpilotRef = 'main',
    this.openIssueOnFailure = false,
    this.secrets = const [],
  });

  /// The cron expression of the schedule; null when there is none.
  String? get cron => switch (schedule) {
        CiSchedulePreset.none => null,
        CiSchedulePreset.custom => customCron.trim(),
        _ => schedule.cron,
      };

  bool get scheduled => cron != null;

  CiOptions copyWith({
    Object? environment = _keep,
    Object? collection = _keep,
    String? workspacePath,
    CiSchedulePreset? schedule,
    String? customCron,
    bool? failOnSkip,
    bool? allowProduction,
    bool? bail,
    String? postpilotRef,
    bool? openIssueOnFailure,
    List<CiSecret>? secrets,
  }) =>
      CiOptions(
        environment: identical(environment, _keep) ? this.environment : environment as String?,
        collection: identical(collection, _keep) ? this.collection : collection as String?,
        workspacePath: workspacePath ?? this.workspacePath,
        schedule: schedule ?? this.schedule,
        customCron: customCron ?? this.customCron,
        failOnSkip: failOnSkip ?? this.failOnSkip,
        allowProduction: allowProduction ?? this.allowProduction,
        bail: bail ?? this.bail,
        postpilotRef: postpilotRef ?? this.postpilotRef,
        openIssueOnFailure: openIssueOnFailure ?? this.openIssueOnFailure,
        secrets: secrets ?? this.secrets,
      );

  static const Object _keep = Object();
}
