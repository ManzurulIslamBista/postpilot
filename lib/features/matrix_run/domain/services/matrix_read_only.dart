import '../../../../core/enums/http_method.dart';

/// "Read-only requests only": a matrix run sends every request once per column, so replaying a write across three
/// environments writes three times. By HTTP method alone and on purpose strict: GET, HEAD and OPTIONS. A POST that only
/// reads (an Odoo `search_read`) is left out too; untick the option to send it.
abstract final class MatrixReadOnly {
  static bool allows(HttpMethod method) =>
      method == HttpMethod.get || method == HttpMethod.head || method == HttpMethod.options;

  /// The same judgement for a method written as text (`get`, `POST`), as the command line has it.
  static bool allowsLabel(String method) {
    final m = method.toUpperCase();
    return m == 'GET' || m == 'HEAD' || m == 'OPTIONS';
  }
}
