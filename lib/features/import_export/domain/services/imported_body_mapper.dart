import '../../../../core/enums/body_type.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_body.dart';

/// Shared body/header helpers of the importers that read a captured request
/// (Insomnia, HAR, cURL scripts).
abstract final class ImportedBodyMapper {
  static const contentTypeHeader = 'Content-Type';

  static RawContentType rawTypeOf(String mimeType) {
    final essence = _essence(mimeType);
    return switch (essence) {
      final t when t.contains('json') => RawContentType.json,
      final t when t.contains('xml') => RawContentType.xml,
      final t when t.contains('html') => RawContentType.html,
      final t when t.contains('javascript') => RawContentType.javascript,
      _ => RawContentType.text,
    };
  }

  /// The second value is a `Content-Type` to send explicitly: set only when
  /// [RawContentType] can't express [mimeType] (`application/vnd.api+json`,
  /// `text/xml`, `application/x-yaml`), because the request builder derives
  /// the header from the raw type when none is given.
  static (RequestBody, String?) raw(String mimeType, String text) {
    final type = rawTypeOf(mimeType);
    final essence = _essence(mimeType);
    final explicit = essence.isEmpty || essence == type.mimeType ? null : mimeType.trim();
    return (RequestBody(type: BodyType.raw, rawContentType: type, rawText: text), explicit);
  }

  /// A JSON-looking text is JSON, anything else plain text: the guess for a
  /// body that arrives without a declared media type.
  static RawContentType sniffRawType(String text) {
    final head = text.trimLeft();
    return head.startsWith('{') || head.startsWith('[') ? RawContentType.json : RawContentType.text;
  }

  static bool hasContentType(List<KeyValueItem> headers) =>
      headers.any((h) => h.key.toLowerCase() == contentTypeHeader.toLowerCase());

  static String _essence(String mimeType) => mimeType.split(';').first.trim().toLowerCase();
}
