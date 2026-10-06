import 'dart:convert';
import '../../../../core/enums/auth_type.dart';
import '../../domain/entities/key_value_item.dart';
import '../../domain/entities/request_auth.dart';

/// Encodes/decodes the JSON columns Requests are persisted with in SQLite —
/// an internal storage detail, not a domain type.
abstract final class RequestJsonCodec {
  /// A text row is `{key, value, enabled}`; a form-data file row also says `kind: file` (see [KeyValueItem.toJson]).
  static String encodeKeyValues(List<KeyValueItem> items) => jsonEncode([for (final i in items) i.toJson()]);

  static List<KeyValueItem> decodeKeyValues(String json) => [
        for (final e in (jsonDecode(json) as List)) ?KeyValueItem.tryFromJson(e),
      ];

  static String encodeAuth(RequestAuth auth) => jsonEncode(auth.toJson());

  /// The dedicated `authType` column wins over any `type` inside the JSON.
  static RequestAuth decodeAuth(String authType, String json) =>
      RequestAuth.fromJson(jsonDecode(json) as Map<String, dynamic>).copyWith(
        type: AuthType.values.firstWhere((t) => t.name == authType, orElse: () => AuthType.inherit),
      );
}
