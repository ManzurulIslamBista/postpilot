import 'dart:convert';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../settings/domain/entities/settings_json.dart';
import '../../../cleanup_ledger/domain/entities/cleanup_settings.dart';

/// How long the retry waits grow: the same every time, or doubling (up to a ceiling).
enum BackoffKind {
  fixed('Fixed'),
  exponential('Exponential');

  final String label;
  const BackoffKind(this.label);
}

/// The status tokens a retry can name: a whole class (`5xx`) or one code (`429`). Kept as text so the stored
/// settings read the way people write them.
abstract final class StatusTokens {
  static final _code = RegExp(r'^[1-5]\d\d$');
  static final _group = RegExp(r'^[45]xx$');

  /// [text] as a stored token, or null when it is neither a code from 100 to 599 nor `4xx` / `5xx`.
  static String? normalize(String text) {
    final token = text.trim().toLowerCase();
    return _group.hasMatch(token) || _code.hasMatch(token) ? token : null;
  }

  /// Every token in [text] (separated by commas, spaces or semicolons), duplicates and unreadable parts dropped.
  static List<String> parseList(String text) {
    final seen = <String>{};
    return [
      for (final part in text.split(RegExp(r'[\s,;]+')))
        if (normalize(part) case final token? when seen.add(token)) token,
    ];
  }

  static bool matches(String token, int status) =>
      token.endsWith('xx') ? status ~/ 100 == int.parse(token[0]) : status == int.parse(token);
}

/// Retry the request when the network fails or the server answers with one of [statuses], waiting between
/// attempts. A request that is not safe to repeat (POST, PATCH, DELETE) is only retried when the person ticked
/// [FlowSettings.repeatUnsafe].
final class RetryPolicy {
  static const maxRetriesLimit = 10;
  static const maxDelayLimitMs = 600000;
  static const maxTotalLimitSeconds = 3600;
  static const defaultStatuses = ['5xx', '429'];

  final bool enabled;

  /// Retries after the first attempt: 3 means up to 4 attempts in all.
  final int maxRetries;
  final bool onNetworkError;
  final List<String> statuses;
  final BackoffKind backoff;

  /// The wait before the first retry; [BackoffKind.exponential] doubles it for each one after.
  final int delayMs;

  /// The longest a single wait grows to.
  final int maxDelayMs;

  /// Wait a random 50-100% of the planned time, so many clients do not retry in step.
  final bool jitter;

  /// Wait as long as a `Retry-After` header asks, instead of the planned time.
  final bool honourRetryAfter;

  /// Give up once this many seconds have passed since the first attempt, whatever is left of [maxRetries].
  final int maxTotalSeconds;

  const RetryPolicy({
    this.enabled = false,
    this.maxRetries = 3,
    this.onNetworkError = true,
    this.statuses = defaultStatuses,
    this.backoff = BackoffKind.exponential,
    this.delayMs = 1000,
    this.maxDelayMs = 30000,
    this.jitter = true,
    this.honourRetryAfter = true,
    this.maxTotalSeconds = 60,
  });

  factory RetryPolicy.fromJson(Object? json) {
    final map = SettingsJson.objectOf(json);
    const defaults = RetryPolicy();
    final statuses = map['statuses'];
    return RetryPolicy(
      enabled: SettingsJson.boolOr(map['enabled'], defaults.enabled),
      maxRetries: SettingsJson.intOr(map['maxRetries'], defaults.maxRetries, min: 1, max: maxRetriesLimit),
      onNetworkError: SettingsJson.boolOr(map['onNetworkError'], defaults.onNetworkError),
      statuses: statuses is List ? StatusTokens.parseList(statuses.whereType<String>().join(' ')) : defaults.statuses,
      backoff: SettingsJson.enumOr(map['backoff'], BackoffKind.values, defaults.backoff),
      delayMs: SettingsJson.intOr(map['delayMs'], defaults.delayMs, min: 0, max: maxDelayLimitMs),
      maxDelayMs: SettingsJson.intOr(map['maxDelayMs'], defaults.maxDelayMs, min: 0, max: maxDelayLimitMs),
      jitter: SettingsJson.boolOr(map['jitter'], defaults.jitter),
      honourRetryAfter: SettingsJson.boolOr(map['retryAfter'], defaults.honourRetryAfter),
      maxTotalSeconds: SettingsJson.intOr(map['maxSeconds'], defaults.maxTotalSeconds, min: 1, max: maxTotalLimitSeconds),
    );
  }

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'maxRetries': maxRetries,
        'onNetworkError': onNetworkError,
        'statuses': statuses,
        'backoff': backoff.name,
        'delayMs': delayMs,
        'maxDelayMs': maxDelayMs,
        'jitter': jitter,
        'retryAfter': honourRetryAfter,
        'maxSeconds': maxTotalSeconds,
      };

  RetryPolicy copyWith({
    bool? enabled,
    int? maxRetries,
    bool? onNetworkError,
    List<String>? statuses,
    BackoffKind? backoff,
    int? delayMs,
    int? maxDelayMs,
    bool? jitter,
    bool? honourRetryAfter,
    int? maxTotalSeconds,
  }) =>
      RetryPolicy(
        enabled: enabled ?? this.enabled,
        maxRetries: _clamp(maxRetries ?? this.maxRetries, 1, maxRetriesLimit),
        onNetworkError: onNetworkError ?? this.onNetworkError,
        statuses: statuses ?? this.statuses,
        backoff: backoff ?? this.backoff,
        delayMs: _clamp(delayMs ?? this.delayMs, 0, maxDelayLimitMs),
        maxDelayMs: _clamp(maxDelayMs ?? this.maxDelayMs, 0, maxDelayLimitMs),
        jitter: jitter ?? this.jitter,
        honourRetryAfter: honourRetryAfter ?? this.honourRetryAfter,
        maxTotalSeconds: _clamp(maxTotalSeconds ?? this.maxTotalSeconds, 1, maxTotalLimitSeconds),
      );

  /// Whether a response with [status] is one to retry.
  bool retriesStatus(int status) => statuses.any((token) => StatusTokens.matches(token, status));

  /// One line for the section header, e.g. `Up to 3 retries on network errors, 5xx and 429, exponential from 1 s`.
  String get summary {
    final causes = [if (onNetworkError) 'network errors', ...statuses];
    final on = causes.isEmpty ? 'nothing selected' : _joinWords(causes);
    final wait = backoff == BackoffKind.exponential ? 'exponential from ${_seconds(delayMs)}' : '${_seconds(delayMs)} apart';
    return 'Up to $maxRetries ${maxRetries == 1 ? 'retry' : 'retries'} on $on, $wait';
  }

  @override
  bool operator ==(Object other) => other is RetryPolicy && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Repeat the request every [intervalMs] until every condition in [until] holds on the response: "poll until the
/// job is done". The conditions are ordinary assertions (status, JSON path, header ...), whose values may use
/// `{{variables}}`. It gives up after [maxAttempts] requests or [maxSeconds], whichever comes first.
final class PollPolicy {
  static const minIntervalMs = 100;
  static const maxIntervalMs = 600000;
  static const maxAttemptsLimit = 1000;
  static const maxSecondsLimit = 3600;

  final bool enabled;
  final List<AssertionEntity> until;
  final int intervalMs;
  final int maxAttempts;
  final int maxSeconds;

  const PollPolicy({
    this.enabled = false,
    this.until = const [],
    this.intervalMs = 2000,
    this.maxAttempts = 30,
    this.maxSeconds = 120,
  });

  factory PollPolicy.fromJson(Object? json) {
    final map = SettingsJson.objectOf(json);
    const defaults = PollPolicy();
    return PollPolicy(
      enabled: SettingsJson.boolOr(map['enabled'], defaults.enabled),
      until: ScriptsJsonCodec.assertionsFromJson(map['until']),
      intervalMs: SettingsJson.intOr(map['intervalMs'], defaults.intervalMs, min: minIntervalMs, max: maxIntervalMs),
      maxAttempts: SettingsJson.intOr(map['maxAttempts'], defaults.maxAttempts, min: 2, max: maxAttemptsLimit),
      maxSeconds: SettingsJson.intOr(map['maxSeconds'], defaults.maxSeconds, min: 1, max: maxSecondsLimit),
    );
  }

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'until': ScriptsJsonCodec.assertionsToJson(until),
        'intervalMs': intervalMs,
        'maxAttempts': maxAttempts,
        'maxSeconds': maxSeconds,
      };

  PollPolicy copyWith({bool? enabled, List<AssertionEntity>? until, int? intervalMs, int? maxAttempts, int? maxSeconds}) =>
      PollPolicy(
        enabled: enabled ?? this.enabled,
        until: until ?? this.until,
        intervalMs: _clamp(intervalMs ?? this.intervalMs, minIntervalMs, maxIntervalMs),
        maxAttempts: _clamp(maxAttempts ?? this.maxAttempts, 2, maxAttemptsLimit),
        maxSeconds: _clamp(maxSeconds ?? this.maxSeconds, 1, maxSecondsLimit),
      );

  /// A poll with nothing to wait for would stop at the first response, so it counts as off.
  bool get isActive => enabled && until.isNotEmpty;

  String get summary => until.isEmpty
      ? 'Add a condition to wait for'
      : 'Every ${_seconds(intervalMs)} until ${until.length == 1 ? until.single.name : '${until.length} conditions hold'}, '
          'at most $maxAttempts requests or $maxSeconds s';

  @override
  bool operator ==(Object other) => other is PollPolicy && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

enum RunConditionKind {
  variableEquals('Variable equals'),
  variableNotEquals('Variable does not equal'),
  variableExists('Variable exists'),
  variableMissing('Variable is not defined'),
  variableNotEmpty('Variable is not empty'),
  environmentIs('Environment is'),
  environmentIsNot('Environment is not'),
  previousPassed('Previous request passed'),
  previousFailed('Previous request failed');

  final String label;
  const RunConditionKind(this.label);

  bool get isVariable => switch (this) {
        variableEquals || variableNotEquals || variableExists || variableMissing || variableNotEmpty => true,
        _ => false,
      };

  bool get isEnvironment => this == environmentIs || this == environmentIsNot;

  /// Whether [RunCondition.name] (the variable or environment name) applies.
  bool get usesName => isVariable || isEnvironment;

  /// Whether [RunCondition.value] (what the variable is compared with) applies.
  bool get usesValue => this == variableEquals || this == variableNotEquals;
}

/// One check made before a request is sent in a run. [name] is the variable (`region`, also written `{{region}}`)
/// or the environment it is about; [value] is what a variable is compared with and may use `{{variables}}`.
/// [id] is session-only, only there so editor rows keep a stable key.
final class RunCondition {
  static int _nextId = 0;

  final int id;
  final RunConditionKind kind;
  final String name;
  final String value;

  RunCondition({int? id, required this.kind, this.name = '', this.value = ''}) : id = id ?? _nextId++;

  RunCondition copyWith({RunConditionKind? kind, String? name, String? value}) =>
      RunCondition(id: id, kind: kind ?? this.kind, name: name ?? this.name, value: value ?? this.value);

  /// The variable name without `{{ }}` or surrounding blanks.
  String get variableName {
    final text = name.trim();
    return text.startsWith('{{') && text.endsWith('}}') ? text.substring(2, text.length - 2).trim() : text;
  }

  /// Why this condition cannot be evaluated as written, or null when it can.
  String? get error => kind.usesName && (kind.isVariable ? variableName : name.trim()).isEmpty
      ? (kind.isVariable ? 'Enter a variable name' : 'Enter an environment name')
      : null;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        if (kind.usesName) 'name': name,
        if (kind.usesValue) 'value': value,
      };

  /// Conditions of an unknown kind (written by a newer build) are left out rather than guessed at.
  static List<RunCondition> listFromJson(Object? list) => [
        if (list is List)
          for (final item in list)
            if (item is Map)
              if (RunConditionKind.values.where((k) => k.name == item['kind']).firstOrNull case final kind?)
                RunCondition(
                  kind: kind,
                  name: SettingsJson.stringOr(item['name'], ''),
                  value: SettingsJson.stringOr(item['value'], ''),
                ),
      ];

  /// A readable form, e.g. `{{region}} equals "eu"`.
  String get text => switch (kind) {
        RunConditionKind.variableEquals => '{{$variableName}} equals "$value"',
        RunConditionKind.variableNotEquals => '{{$variableName}} does not equal "$value"',
        RunConditionKind.variableExists => '{{$variableName}} is defined',
        RunConditionKind.variableMissing => '{{$variableName}} is not defined',
        RunConditionKind.variableNotEmpty => '{{$variableName}} is not empty',
        RunConditionKind.environmentIs => 'the environment is "${name.trim()}"',
        RunConditionKind.environmentIsNot => 'the environment is not "${name.trim()}"',
        RunConditionKind.previousPassed => 'the previous request passed',
        RunConditionKind.previousFailed => 'the previous request failed',
      };
}

/// Send the request in a run only when every condition holds; otherwise it is skipped (not failed), with the
/// reason shown.
final class RunIfPolicy {
  final bool enabled;
  final List<RunCondition> conditions;

  const RunIfPolicy({this.enabled = false, this.conditions = const []});

  factory RunIfPolicy.fromJson(Object? json) {
    final map = SettingsJson.objectOf(json);
    return RunIfPolicy(
      enabled: SettingsJson.boolOr(map['enabled'], false),
      conditions: RunCondition.listFromJson(map['all']),
    );
  }

  Map<String, Object?> toJson() => {'enabled': enabled, 'all': [for (final c in conditions) c.toJson()]};

  RunIfPolicy copyWith({bool? enabled, List<RunCondition>? conditions}) =>
      RunIfPolicy(enabled: enabled ?? this.enabled, conditions: conditions ?? this.conditions);

  bool get isActive => enabled && conditions.isNotEmpty;

  String get summary => conditions.isEmpty
      ? 'Add a condition'
      : 'Only when ${conditions.map((c) => c.text).join(' and ')}';

  @override
  bool operator ==(Object other) => other is RunIfPolicy && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// What a request does around being sent, instead of a script: retry, poll, run-if. Stored under the `flow` key of
/// the request's settings; a request with none stores nothing.
final class FlowSettings {
  final RetryPolicy retry;
  final PollPolicy poll;
  final RunIfPolicy runIf;

  /// In a run with "stop on failure", still run this request after one failed (a cleanup). It does not override
  /// the person pressing Stop, and its own Run if conditions still apply.
  final bool alwaysRun;

  /// "I know this is safe": the request may be repeated (retry, poll, more pages) although it is a POST, PATCH or
  /// DELETE, which can change data each time.
  final bool repeatUnsafe;

  /// "Clean up what this request creates": delete the records it made once a run is done (see `CleanupLedger`).
  final CleanupSettings cleanup;

  const FlowSettings({
    this.retry = const RetryPolicy(),
    this.poll = const PollPolicy(),
    this.runIf = const RunIfPolicy(),
    this.alwaysRun = false,
    this.repeatUnsafe = false,
    this.cleanup = CleanupSettings.none,
  });

  static const none = FlowSettings();

  factory FlowSettings.fromJson(Object? json) {
    final map = SettingsJson.objectOf(json);
    return FlowSettings(
      retry: RetryPolicy.fromJson(map['retry']),
      poll: PollPolicy.fromJson(map['poll']),
      runIf: RunIfPolicy.fromJson(map['runIf']),
      alwaysRun: SettingsJson.boolOr(map['alwaysRun'], false),
      repeatUnsafe: SettingsJson.boolOr(map['repeatUnsafe'], false),
      cleanup: CleanupSettings.fromJson(map['cleanup']),
    );
  }

  /// Only what differs from the defaults, so a request without flow settings adds no key.
  Map<String, Object?> toJson() => {
        if (retry != const RetryPolicy()) 'retry': retry.toJson(),
        if (poll != const PollPolicy()) 'poll': poll.toJson(),
        if (runIf != const RunIfPolicy()) 'runIf': runIf.toJson(),
        if (alwaysRun) 'alwaysRun': true,
        if (repeatUnsafe) 'repeatUnsafe': true,
        if (!cleanup.isEmpty) 'cleanup': cleanup.toJson(),
      };

  bool get isEmpty => this == none;

  FlowSettings copyWith({
    RetryPolicy? retry,
    PollPolicy? poll,
    RunIfPolicy? runIf,
    bool? alwaysRun,
    bool? repeatUnsafe,
    CleanupSettings? cleanup,
  }) =>
      FlowSettings(
        retry: retry ?? this.retry,
        poll: poll ?? this.poll,
        runIf: runIf ?? this.runIf,
        alwaysRun: alwaysRun ?? this.alwaysRun,
        repeatUnsafe: repeatUnsafe ?? this.repeatUnsafe,
        cleanup: cleanup ?? this.cleanup,
      );

  /// Whether retry or poll is on (what a send does by itself; Run if and Always run only matter in a run).
  bool get repeatsRequest => retry.enabled || poll.isActive;

  @override
  bool operator ==(Object other) => other is FlowSettings && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

int _clamp(int value, int min, int max) => value < min ? min : (value > max ? max : value);

String _seconds(int ms) {
  if (ms < 1000) return '$ms ms';
  final seconds = ms / 1000;
  return '${seconds == seconds.truncateToDouble() ? seconds.toInt() : seconds.toStringAsFixed(1)} s';
}

String _joinWords(List<String> words) =>
    words.length < 2 ? words.join() : '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';
