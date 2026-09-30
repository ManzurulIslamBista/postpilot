import '../entities/extractor_entity.dart';
import 'response_reader.dart';

abstract final class ExtractorValueResolver {
  /// `null` when the path/header isn't in the response.
  static String? resolve(ResponseReader reader, ExtractorEntity extractor) => switch (extractor.source) {
        ExtractorSource.jsonPath => _fromJson(reader, extractor.path),
        ExtractorSource.header => reader.header(extractor.path),
      };

  static String? _fromJson(ResponseReader reader, String path) {
    final value = reader.jsonPath(path);
    return value == null ? null : ResponseReader.stringify(value);
  }
}
