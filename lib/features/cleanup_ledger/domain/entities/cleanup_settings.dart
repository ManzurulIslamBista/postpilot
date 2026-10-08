// Pure Dart (no Flutter): the app, the command line and the tests read the same settings.
import 'dart:convert';
import '../../../settings/domain/entities/settings_json.dart';

/// What undoes a record the request created.
enum CleanupUndo {
  /// Decided from the request: an Odoo `create` is undone with `unlink`, any other POST with a REST DELETE.
  auto('Automatic'),

  /// `POST <same server>/json/2/<model>/unlink` with the created ids (the call_kw form on an Odoo 18 or older URL).
  odooUnlink('Odoo unlink'),

  /// `DELETE <the request's URL>/<id>`.
  restDelete('REST DELETE'),

  /// Another request of the same collection, sent with `{{created.id}}`, `{{created.ids}}` and the fields of the response.
  request('Another request');

  final String label;
  const CleanupUndo(this.label);
}

/// "Clean up what this request creates": where the created id is in the response and how to undo it. Stored under the
/// `cleanup` key of the request's flow settings (`flow.cleanup`), so it needs no new column and travels with the request
/// through a backup, a workspace file and Git. It holds no secret: a JSON path and the name of a request.
final class CleanupSettings {
  static const none = CleanupSettings();

  final bool enabled;

  /// A JSON path to the created id (or list of ids) in the response; blank looks in the usual places.
  final String idPath;
  final CleanupUndo undo;

  /// The undo request when [undo] is [CleanupUndo.request]: its name (`Delete partner`), or with the folders above it
  /// (`Partners/Delete partner`), the same selector `postpilot run --request` takes. A name is kept instead of an id
  /// because ids differ between machines, backups and Git checkouts.
  final String request;

  const CleanupSettings({this.enabled = false, this.idPath = '', this.undo = CleanupUndo.auto, this.request = ''});

  factory CleanupSettings.fromJson(Object? json) {
    final map = SettingsJson.objectOf(json);
    return CleanupSettings(
      enabled: SettingsJson.boolOr(map['enabled'], false),
      idPath: SettingsJson.stringOr(map['idPath'], ''),
      undo: SettingsJson.enumOr(map['undo'], CleanupUndo.values, CleanupUndo.auto),
      request: SettingsJson.stringOr(map['request'], ''),
    );
  }

  /// Only what differs from the defaults, so a request without cleanup adds no key.
  Map<String, Object?> toJson() => {
        if (enabled) 'enabled': true,
        if (idPath.trim().isNotEmpty) 'idPath': idPath.trim(),
        if (undo != CleanupUndo.auto) 'undo': undo.name,
        if (request.trim().isNotEmpty) 'request': request.trim(),
      };

  bool get isEmpty => this == none;

  CleanupSettings copyWith({bool? enabled, String? idPath, CleanupUndo? undo, String? request}) => CleanupSettings(
        enabled: enabled ?? this.enabled,
        idPath: idPath ?? this.idPath,
        undo: undo ?? this.undo,
        request: request ?? this.request,
      );

  /// The id path to look at; blank means "look in the usual places".
  String get effectiveIdPath => idPath.trim();

  /// One line for the section header.
  String get summary {
    if (!enabled) return 'Delete the records this request creates when a run is done';
    final where = effectiveIdPath.isEmpty ? 'id found automatically' : 'id at $effectiveIdPath';
    final how = undo == CleanupUndo.request
        ? (request.trim().isEmpty ? 'undo request not chosen yet' : 'undone by "${request.trim()}"')
        : 'undone by ${undo.label.toLowerCase()}';
    return '$where, $how';
  }

  @override
  bool operator ==(Object other) => other is CleanupSettings && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
