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
}
