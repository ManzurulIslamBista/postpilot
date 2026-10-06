import 'dart:convert';
import '../../../request_flow/domain/entities/flow_settings.dart';
import '../../../request_flow/domain/entities/pagination_settings.dart';
import '../../../test_suggestions/domain/entities/baseline_settings.dart';
import 'app_settings.dart';
import 'settings_json.dart';

/// Per-request overrides of [AppSettings]. A null field means "use the global
/// setting", so an untouched request stores nothing.
///
/// The row also holds what a request does around being sent, which has no global
/// counterpart: [flow] (retry, poll until, run if) and [pagination] (fetch all pages).
/// They are stored under the `flow` and `pagination` keys, and a request that sets
/// none of them has neither key. [baseline] (enforce the recorded response baseline in runs) is stored under `baseline`.
final class RequestSettings {
  final bool? followRedirects;
  final bool? verifySsl;

  /// 0 waits forever for this request.
  final int? timeoutSeconds;
  final bool? sendNoCacheHeader;

  /// Retry, poll until, run if and always run; [FlowSettings.none] when the request has none.
  final FlowSettings flow;

  /// Fetch all pages; [PaginationSettings.none] when the request has none.
  final PaginationSettings pagination;

  /// Whether runs hold the response to its recorded baseline; [BaselineSettings.none] when they do not.
  final BaselineSettings baseline;

  const RequestSettings({
    this.followRedirects,
    this.verifySsl,
    this.timeoutSeconds,
    this.sendNoCacheHeader,
    this.flow = FlowSettings.none,
    this.pagination = PaginationSettings.none,
    this.baseline = BaselineSettings.none,
  });

  static const none = RequestSettings();

  factory RequestSettings.fromJson(Map<String, dynamic> json) => RequestSettings(
        followRedirects: SettingsJson.boolOrNull(json['followRedirects']),
        verifySsl: SettingsJson.boolOrNull(json['verifySsl']),
        timeoutSeconds: SettingsJson.intOrNull(json['timeoutSeconds'], min: 0, max: AppSettings.maxTimeoutSeconds),
        sendNoCacheHeader: SettingsJson.boolOrNull(json['sendNoCacheHeader']),
        flow: FlowSettings.fromJson(json['flow']),
        pagination: PaginationSettings.fromJson(json['pagination']),
        baseline: BaselineSettings.fromJson(json['baseline']),
      );

  /// The overrides stored as [source]; none when it is missing or unreadable.
  factory RequestSettings.decode(String? source) => RequestSettings.fromJson(SettingsJson.decodeObject(source));

  /// Nothing is set at all, so nothing is stored.
  bool get isEmpty => !hasOverrides && flow.isEmpty && pagination.isEmpty && baseline.isEmpty;

  /// Whether any of the four overrides of the global settings is set (what the Settings tab can reset).
  bool get hasOverrides =>
      followRedirects != null || verifySsl != null || timeoutSeconds != null || sendNoCacheHeader != null;

  Map<String, dynamic> toJson() => {
        if (followRedirects != null) 'followRedirects': followRedirects,
        if (verifySsl != null) 'verifySsl': verifySsl,
        if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
        if (sendNoCacheHeader != null) 'sendNoCacheHeader': sendNoCacheHeader,
        if (!flow.isEmpty) 'flow': flow.toJson(),
        if (!pagination.isEmpty) 'pagination': pagination.toJson(),
        if (!baseline.isEmpty) 'baseline': baseline.toJson(),
      };

  String encode() => jsonEncode(toJson());

  // Not one copyWith: null is a real value here ("use global"), so it could
  // not be told apart from "leave unchanged".
  RequestSettings withFollowRedirects(bool? value) => RequestSettings(
        followRedirects: value,
        verifySsl: verifySsl,
        timeoutSeconds: timeoutSeconds,
        sendNoCacheHeader: sendNoCacheHeader,
        flow: flow,
        pagination: pagination,
        baseline: baseline,
      );

  RequestSettings withVerifySsl(bool? value) => RequestSettings(
        followRedirects: followRedirects,
        verifySsl: value,
        timeoutSeconds: timeoutSeconds,
        sendNoCacheHeader: sendNoCacheHeader,
        flow: flow,
        pagination: pagination,
        baseline: baseline,
      );

  RequestSettings withTimeoutSeconds(int? value) => RequestSettings(
        followRedirects: followRedirects,
        verifySsl: verifySsl,
        timeoutSeconds: value,
        sendNoCacheHeader: sendNoCacheHeader,
        flow: flow,
        pagination: pagination,
        baseline: baseline,
      );

  RequestSettings withSendNoCacheHeader(bool? value) => RequestSettings(
        followRedirects: followRedirects,
        verifySsl: verifySsl,
        timeoutSeconds: timeoutSeconds,
        sendNoCacheHeader: value,
        flow: flow,
        pagination: pagination,
        baseline: baseline,
      );

  RequestSettings withFlow(FlowSettings value) => RequestSettings(
        followRedirects: followRedirects,
        verifySsl: verifySsl,
        timeoutSeconds: timeoutSeconds,
        sendNoCacheHeader: sendNoCacheHeader,
        flow: value,
        pagination: pagination,
        baseline: baseline,
      );

  RequestSettings withPagination(PaginationSettings value) => RequestSettings(
        followRedirects: followRedirects,
        verifySsl: verifySsl,
        timeoutSeconds: timeoutSeconds,
        sendNoCacheHeader: sendNoCacheHeader,
        flow: flow,
        pagination: value,
        baseline: baseline,
      );

  RequestSettings withBaseline(BaselineSettings value) => RequestSettings(
        followRedirects: followRedirects,
        verifySsl: verifySsl,
        timeoutSeconds: timeoutSeconds,
        sendNoCacheHeader: sendNoCacheHeader,
        flow: flow,
        pagination: pagination,
        baseline: value,
      );

  /// The same flow, pagination and baseline setting without the four overrides: what "use global settings for everything" resets to.
  RequestSettings withoutOverrides() => RequestSettings(flow: flow, pagination: pagination, baseline: baseline);

  @override
  bool operator ==(Object other) =>
      other is RequestSettings &&
      other.followRedirects == followRedirects &&
      other.verifySsl == verifySsl &&
      other.timeoutSeconds == timeoutSeconds &&
      other.sendNoCacheHeader == sendNoCacheHeader &&
      other.flow == flow &&
      other.pagination == pagination &&
      other.baseline == baseline;

  @override
  int get hashCode => Object.hash(followRedirects, verifySsl, timeoutSeconds, sendNoCacheHeader, flow, pagination, baseline);
}
