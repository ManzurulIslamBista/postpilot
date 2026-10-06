import '../../../settings/domain/entities/settings_json.dart';

/// What a request does with its recorded baseline, stored under the `baseline` key of its settings (so it
/// travels with the workspace file, while the baseline itself stays on the device that recorded it). A request
/// with nothing set stores no key.
final class BaselineSettings {
  /// A run (the collection runner, the command line) fails the request when its response drifted from the
  /// baseline in a breaking way.
  final bool enforce;

  const BaselineSettings({this.enforce = false});

  static const none = BaselineSettings();

  factory BaselineSettings.fromJson(Object? json) =>
      BaselineSettings(enforce: SettingsJson.boolOr(SettingsJson.objectOf(json)['enforce'], false));

  bool get isEmpty => !enforce;

  Map<String, Object?> toJson() => {if (enforce) 'enforce': true};

  BaselineSettings copyWith({bool? enforce}) => BaselineSettings(enforce: enforce ?? this.enforce);

  @override
  bool operator ==(Object other) => other is BaselineSettings && other.enforce == enforce;

  @override
  int get hashCode => enforce.hashCode;
}
