import '../entities/api_docs_model.dart';
import 'api_docs_html_writer.dart';
import 'api_docs_markdown_writer.dart';
import 'secret_masker.dart';

/// Renders a collection's documentation. Both outputs go through
/// [SecretMasker] first, so a secret cannot reach either of them.
abstract final class ApiDocsGenerator {
  static String toMarkdown(ApiDocsModel model) => ApiDocsMarkdownWriter().write(SecretMasker.redact(model));

  static String toHtml(ApiDocsModel model) => ApiDocsHtmlWriter().write(SecretMasker.redact(model));
}
