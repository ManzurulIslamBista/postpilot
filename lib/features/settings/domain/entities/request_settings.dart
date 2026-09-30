import 'dart:convert';
import 'app_settings.dart';
import 'settings_json.dart';

/// Per-request overrides of [AppSettings]. A null field means "use the global
/// setting", so an untouched request stores nothing.
final class RequestSettings {
  final bool? followRedirects;
  final bool? verifySsl;

  /// 0 waits forever for this request.
  final int? timeoutSeconds;
  final bool? sendNoCacheHeader;

  const RequestSettings({this.followRedirects, this.verifySsl, this.timeoutSeconds, this.sendNoCacheHeader});

  static const none = RequestSettings();

  factory RequestSettings.fromJson(Map<String, dynamic> json) => RequestSettings(
        followRedirects: SettingsJson.boolOrNull(json['followRedirects']),
        verifySsl: SettingsJson.boolOrNull(json['verifySsl']),
        timeoutSeconds: SettingsJson.intOrNull(json['timeoutSeconds'], min: 0, max: AppSettings.maxTimeoutSeconds),
        sendNoCacheHeader: SettingsJson.boolOrNull(json['sendNoCacheHeader']),
      );

  /// The overrides stored as [source]; none when it is missing or unreadable.
  factory RequestSettings.decode(String? source) => RequestSettings.fromJson(SettingsJson.decodeObject(source));

  bool get isEmpty =>
      followRedirects == null && verifySsl == null && timeoutSeconds == null && sendNoCacheHeader == null;

  Map<String, dynamic> toJson() => {
        if (followRedirects != null) 'followRedirects': followRedirects,
        if (verifySsl != null) 'verifySsl': verifySsl,
        if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
        if (sendNoCacheHeader != null) 'sendNoCacheHeader': sendNoCacheHeader,
      };

  String encode() => jsonEncode(toJson());

  // Not one copyWith: null is a real value here ("use global"), so it could
  // not be told apart from "leave unchanged".
  RequestSettings withFollowRedirects(bool? value) => RequestSettings(
        followRedirects: value,
        verifySsl: verifySsl,
        timeoutSeconds: timeoutSeconds,
        sendNoCacheHeader: sendNoCacheHeader,
      );

  RequestSettings withVerifySsl(bool? value) => RequestSettings(
        followRedirects: followRedirects,
        verifySsl: value,
        timeoutSeconds: timeoutSeconds,
        sendNoCacheHeader: sendNoCacheHeader,
      );

  RequestSettings withTimeoutSeconds(int? value) => RequestSettings(
        followRedirects: followRedirects,
        verifySsl: verifySsl,
        timeoutSeconds: value,
        sendNoCacheHeader: sendNoCacheHeader,
      );

  RequestSettings withSendNoCacheHeader(bool? value) => RequestSettings(
        followRedirects: followRedirects,
        verifySsl: verifySsl,
        timeoutSeconds: timeoutSeconds,
        sendNoCacheHeader: value,
      );

  @override
  bool operator ==(Object other) =>
      other is RequestSettings &&
      other.followRedirects == followRedirects &&
      other.verifySsl == verifySsl &&
      other.timeoutSeconds == timeoutSeconds &&
      other.sendNoCacheHeader == sendNoCacheHeader;

  @override
  int get hashCode => Object.hash(followRedirects, verifySsl, timeoutSeconds, sendNoCacheHeader);
}
