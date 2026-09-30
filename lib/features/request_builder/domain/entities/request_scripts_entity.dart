/// Per-request test assertions and response->variable extractors. Both are
/// raw JSON arrays; the feature that defines their item shape owns the codec.
final class RequestScriptsEntity {
  final int requestId;
  final String assertionsJson;
  final String extractorsJson;

  const RequestScriptsEntity({
    required this.requestId,
    this.assertionsJson = '[]',
    this.extractorsJson = '[]',
  });

  RequestScriptsEntity copyWith({String? assertionsJson, String? extractorsJson}) => RequestScriptsEntity(
        requestId: requestId,
        assertionsJson: assertionsJson ?? this.assertionsJson,
        extractorsJson: extractorsJson ?? this.extractorsJson,
      );
}
