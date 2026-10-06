import '../../../../core/enums/body_type.dart';
import 'key_value_item.dart';

final class RequestBody {
  final BodyType type;
  final RawContentType rawContentType;
  final String rawText;
  final List<KeyValueItem> formFields;
  final List<KeyValueItem> urlEncodedFields;
  final String graphqlQuery;
  final String graphqlVariables;

  const RequestBody({
    this.type = BodyType.none,
    this.rawContentType = RawContentType.json,
    this.rawText = '',
    this.formFields = const [],
    this.urlEncodedFields = const [],
    this.graphqlQuery = '',
    this.graphqlVariables = '{}',
  });

  RequestBody copyWith({
    BodyType? type,
    RawContentType? rawContentType,
    String? rawText,
    List<KeyValueItem>? formFields,
    List<KeyValueItem>? urlEncodedFields,
    String? graphqlQuery,
    String? graphqlVariables,
  }) =>
      RequestBody(
        type: type ?? this.type,
        rawContentType: rawContentType ?? this.rawContentType,
        rawText: rawText ?? this.rawText,
        formFields: formFields ?? this.formFields,
        urlEncodedFields: urlEncodedFields ?? this.urlEncodedFields,
        graphqlQuery: graphqlQuery ?? this.graphqlQuery,
        graphqlVariables: graphqlVariables ?? this.graphqlVariables,
      );

  static const empty = RequestBody();

  /// The file a [BodyType.binary] body sends: the file row without a name in [formFields]. It is kept there, as one
  /// more form row, so that every store that already saves form rows (the database, backups, Git, History) carries
  /// it as it is and no column was added; the form-data editor shows it as a file row that has no key yet, and a
  /// form-data send leaves it out like any row whose key is empty. Null when none was chosen.
  KeyValueItem? get binaryFile {
    for (final field in formFields) {
      if (field.isFile && field.key.isEmpty) return field;
    }
    return null;
  }

  /// This body with [file] as the file of a binary body (an existing one is replaced, null removes it).
  RequestBody withBinaryFile(KeyValueItem? file) {
    final index = formFields.indexWhere((f) => f.isFile && f.key.isEmpty);
    final rows = List<KeyValueItem>.of(formFields);
    if (file == null) {
      if (index != -1) rows.removeAt(index);
    } else {
      final row = file.copyWith(key: '', kind: FormFieldKind.file, enabled: true);
      if (index == -1) {
        rows.add(row);
      } else {
        rows[index] = row;
      }
    }
    return copyWith(formFields: rows);
  }
}
