import 'dart:convert';
import 'proxy_settings.dart';
import 'settings_json.dart';

enum AppThemeMode { system, light, dark }

/// The app-wide settings. Every field has a default, and [fromJson] and
/// [decode] fall back to it for anything missing or malformed.
final class AppSettings {
  static const defaultTimeoutSeconds = 30;
  static const maxTimeoutSeconds = 86400;
  static const defaultMaxRedirects = 10;
  static const maxRedirectsLimit = 100;
  static const defaultMaxResponseSizeMb = 50;
  static const maxResponseSizeMbLimit = 10240;
  static const defaultMaxUploadSizeMb = 100;
  static const maxUploadSizeMbLimit = 10240;

  final AppThemeMode themeMode;

  /// 0 waits forever.
  final int requestTimeoutSeconds;
  final bool followRedirects;
  final int maxRedirects;
  final bool verifySsl;
  final bool sendNoCacheHeader;

  /// 0 keeps whatever size the response is.
  final int maxResponseSizeMb;

  /// The most a request may upload in files (form-data file parts, a binary body); a larger one is refused before
  /// anything is sent. 0 sends any size.
  final int maxUploadSizeMb;
  final bool trimKeysAndValues;
  final ProxySettings proxy;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.requestTimeoutSeconds = defaultTimeoutSeconds,
    this.followRedirects = true,
    this.maxRedirects = defaultMaxRedirects,
    this.verifySsl = true,
    this.sendNoCacheHeader = false,
    this.maxResponseSizeMb = defaultMaxResponseSizeMb,
    this.maxUploadSizeMb = defaultMaxUploadSizeMb,
    this.trimKeysAndValues = false,
    this.proxy = const ProxySettings(),
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode: SettingsJson.enumOr(json['themeMode'], AppThemeMode.values, AppThemeMode.system),
        requestTimeoutSeconds:
            SettingsJson.intOr(json['requestTimeoutSeconds'], defaultTimeoutSeconds, min: 0, max: maxTimeoutSeconds),
        followRedirects: SettingsJson.boolOr(json['followRedirects'], true),
        maxRedirects: SettingsJson.intOr(json['maxRedirects'], defaultMaxRedirects, min: 1, max: maxRedirectsLimit),
        verifySsl: SettingsJson.boolOr(json['verifySsl'], true),
        sendNoCacheHeader: SettingsJson.boolOr(json['sendNoCacheHeader'], false),
        maxResponseSizeMb: SettingsJson.intOr(
          json['maxResponseSizeMb'],
          defaultMaxResponseSizeMb,
          min: 0,
          max: maxResponseSizeMbLimit,
        ),
        maxUploadSizeMb: SettingsJson.intOr(
          json['maxUploadSizeMb'],
          defaultMaxUploadSizeMb,
          min: 0,
          max: maxUploadSizeMbLimit,
        ),
        trimKeysAndValues: SettingsJson.boolOr(json['trimKeysAndValues'], false),
        proxy: ProxySettings.fromJson(SettingsJson.objectOf(json['proxy'])),
      );

  /// The settings stored as [source], or the defaults when there is nothing
  /// stored or it cannot be read.
  factory AppSettings.decode(String? source) => AppSettings.fromJson(SettingsJson.decodeObject(source));

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'requestTimeoutSeconds': requestTimeoutSeconds,
        'followRedirects': followRedirects,
        'maxRedirects': maxRedirects,
        'verifySsl': verifySsl,
        'sendNoCacheHeader': sendNoCacheHeader,
        'maxResponseSizeMb': maxResponseSizeMb,
        'maxUploadSizeMb': maxUploadSizeMb,
        'trimKeysAndValues': trimKeysAndValues,
        'proxy': proxy.toJson(),
      };

  String encode() => jsonEncode(toJson());

  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? requestTimeoutSeconds,
    bool? followRedirects,
    int? maxRedirects,
    bool? verifySsl,
    bool? sendNoCacheHeader,
    int? maxResponseSizeMb,
    int? maxUploadSizeMb,
    bool? trimKeysAndValues,
    ProxySettings? proxy,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        requestTimeoutSeconds: requestTimeoutSeconds ?? this.requestTimeoutSeconds,
        followRedirects: followRedirects ?? this.followRedirects,
        maxRedirects: maxRedirects ?? this.maxRedirects,
        verifySsl: verifySsl ?? this.verifySsl,
        sendNoCacheHeader: sendNoCacheHeader ?? this.sendNoCacheHeader,
        maxResponseSizeMb: maxResponseSizeMb ?? this.maxResponseSizeMb,
        maxUploadSizeMb: maxUploadSizeMb ?? this.maxUploadSizeMb,
        trimKeysAndValues: trimKeysAndValues ?? this.trimKeysAndValues,
        proxy: proxy ?? this.proxy,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.requestTimeoutSeconds == requestTimeoutSeconds &&
      other.followRedirects == followRedirects &&
      other.maxRedirects == maxRedirects &&
      other.verifySsl == verifySsl &&
      other.sendNoCacheHeader == sendNoCacheHeader &&
      other.maxResponseSizeMb == maxResponseSizeMb &&
      other.maxUploadSizeMb == maxUploadSizeMb &&
      other.trimKeysAndValues == trimKeysAndValues &&
      other.proxy == proxy;

  @override
  int get hashCode => Object.hash(
        themeMode,
        requestTimeoutSeconds,
        followRedirects,
        maxRedirects,
        verifySsl,
        sendNoCacheHeader,
        maxResponseSizeMb,
        maxUploadSizeMb,
        trimKeysAndValues,
        proxy,
      );
}
