import '../../../../core/enums/http_method.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/request_body.dart';

/// A format-neutral request tree: what every importer that builds a whole
/// collection (Insomnia, HAR, cURL scripts) hands to `ImportedCollectionWriter`.
sealed class ImportedItem {
  final String name;
  const ImportedItem(this.name);
}

final class ImportedFolder extends ImportedItem {
  final List<ImportedItem> children;
  const ImportedFolder(super.name, this.children);
}

final class ImportedRequest extends ImportedItem {
  final HttpMethod method;
  final String url;
  final List<KeyValueItem> headers;
  final List<KeyValueItem> queryParams;
  final RequestBody body;
  final RequestAuth auth;

  const ImportedRequest(
    super.name, {
    required this.method,
    required this.url,
    this.headers = const [],
    this.queryParams = const [],
    this.body = RequestBody.empty,
    this.auth = const RequestAuth(),
  });
}

final class ImportedCollection {
  final String name;
  final List<ImportedItem> items;

  /// Becomes the collection's variables.
  final List<KeyValueItem> variables;
  final RequestAuth? auth;

  const ImportedCollection(this.name, this.items, {this.variables = const [], this.auth});

  int get folderCount => _count(items, folders: true);
  int get requestCount => _count(items, folders: false);

  static int _count(List<ImportedItem> items, {required bool folders}) {
    var total = 0;
    for (final item in items) {
      switch (item) {
        case ImportedFolder():
          total += (folders ? 1 : 0) + _count(item.children, folders: folders);
        case ImportedRequest():
          total += folders ? 0 : 1;
      }
    }
    return total;
  }
}
