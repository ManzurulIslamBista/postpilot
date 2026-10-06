/// What a form-data row holds: a text value, or a reference to a file.
enum FormFieldKind { text, file }

/// A single header/query-param/form-field row.
///
/// [id] is a locally-assigned, session-only identity (never persisted) —
/// its only job is to give editable-list UIs (see `KeyValueEditor`) a
/// stable [ValueKey] per row so Flutter doesn't reuse one row's
/// [TextFormField] state for a different row after an add/remove/rebuild.
/// Without it, list-position-based widget reuse silently leaks or
/// concatenates text between rows — a real bug this class previously had.
///
/// A form-data row can be a file ([kind] is [FormFieldKind.file]): [value] is then the path of the file (it may
/// hold `{{variables}}`, so a team can share `{{uploadDir}}/avatar.png`), [fileName] the name to send when it is not
/// the file's own, [contentType] the type to send when it is not guessed from the extension. Only this reference is
/// ever stored: the bytes are read from the disk when the request is sent.
final class KeyValueItem {
  static int _nextId = 0;

  final int id;
  final String key;
  final String value;
  final bool enabled;
  final FormFieldKind kind;
  final String fileName;
  final String contentType;

  KeyValueItem({
    int? id,
    required this.key,
    required this.value,
    this.enabled = true,
    this.kind = FormFieldKind.text,
    this.fileName = '',
    this.contentType = '',
  }) : id = id ?? _nextId++;

  bool get isFile => kind == FormFieldKind.file;

  KeyValueItem copyWith({
    String? key,
    String? value,
    bool? enabled,
    FormFieldKind? kind,
    String? fileName,
    String? contentType,
  }) =>
      KeyValueItem(
        id: id,
        key: key ?? this.key,
        value: value ?? this.value,
        enabled: enabled ?? this.enabled,
        kind: kind ?? this.kind,
        fileName: fileName ?? this.fileName,
        contentType: contentType ?? this.contentType,
      );

  /// The stored form, shared by every place that saves rows (the database, a workspace file, a backup, a Git
  /// document, a History snapshot). A text row is exactly `{key, value, enabled}` as it always was; only a file row
  /// adds `kind`, and `fileName` and `contentType` when set, so older files stay valid and an older build reads a
  /// file row as a text row holding the path.
  Map<String, Object?> toJson() => {
        'key': key,
        'value': value,
        'enabled': enabled,
        if (isFile) ...{
          'kind': 'file',
          if (fileName.isNotEmpty) 'fileName': fileName,
          if (contentType.isNotEmpty) 'contentType': contentType,
        },
      };

  /// A row read from stored JSON, tolerating what is missing or of the wrong type (an unknown `kind` is text).
  /// Null when [row] is not an object with a text `key`.
  static KeyValueItem? tryFromJson(Object? row) {
    if (row is! Map || row['key'] is! String) return null;
    final isFile = row['kind'] == 'file';
    String text(String name) => row[name] is String ? row[name] as String : '';
    return KeyValueItem(
      key: row['key'] as String,
      value: text('value'),
      enabled: row['enabled'] != false,
      kind: isFile ? FormFieldKind.file : FormFieldKind.text,
      fileName: isFile ? text('fileName') : '',
      contentType: isFile ? text('contentType') : '',
    );
  }
}
