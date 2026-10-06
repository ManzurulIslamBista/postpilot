import '../../../../core/enums/http_method.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';

/// What a generated request checks.
enum TestCategory {
  /// A valid request built from the schema's examples and defaults: the documented success status and the
  /// documented response schema.
  contract('Contract', 'A valid request: the documented status, content type and response schema'),

  /// Something wrong with the request (a required field left out, a wrong type, no body, broken JSON): a client error.
  negative('Negative', 'Required fields missing one at a time, wrong types, an empty body, broken JSON'),

  /// A value just past what the schema allows (below a minimum, over a maximum, too long, not in the enum, overflow).
  boundary('Boundary', 'Values just outside minimum, maximum, length, enum and item limits'),

  /// No credentials, or malformed ones, for an operation that needs them.
  auth('Auth', 'No credentials and a malformed token on operations that need credentials');

  final String label;
  final String description;
  const TestCategory(this.label, this.description);
}

/// One request the generator proposes, ready to be written into a collection.
final class GeneratedCase {
  final TestCategory category;

  /// `GET /pets/{petId}`: the operation this case belongs to.
  final String operation;

  /// `GET /pets/{petId} (contract)`: the request's name.
  final String name;
  final HttpMethod method;
  final String url;
  final List<KeyValueItem> headers;
  final List<KeyValueItem> queryParams;
  final RequestBody body;
  final RequestAuth auth;
  final List<AssertionEntity> assertions;

  /// The request changes data on the server (POST, PUT, PATCH, DELETE): it only runs when asked to.
  final bool changesData;

  const GeneratedCase({
    required this.category,
    required this.operation,
    required this.name,
    required this.method,
    required this.url,
    required this.headers,
    required this.queryParams,
    required this.body,
    required this.auth,
    required this.assertions,
    required this.changesData,
  });

  /// What the case expects, for the preview: `Status equals 4xx · Body matches the JSON Schema`.
  String get expectation => assertions.map((a) => a.name).join(' · ');
}

/// Everything the generator found in one document.
final class GeneratedSuite {
  /// The cap on how many requests one generation writes unless the person raises it.
  static const defaultCap = 200;

  /// The API's title.
  final String name;

  /// The server of the document, as the importer reads it.
  final String baseUrl;
  final List<GeneratedCase> cases;

  /// What could not be generated and why: an operation the importer skipped, a scheme with no way to build
  /// credentials, a limit too big to build a test value for.
  final List<String> notes;

  const GeneratedSuite({required this.name, required this.baseUrl, required this.cases, this.notes = const []});

  int count(TestCategory category) => cases.where((c) => c.category == category).length;

  int get changesDataCount => cases.where((c) => c.changesData).length;

  int get operationCount => {for (final c in cases) c.operation}.length;

  /// The cases a generation with [categories] ticked and a limit of [cap] requests writes. Over the limit, the
  /// categories come in the order of how much each says per request (contract, auth, negative, boundary) and take
  /// the operations in the order of the document, so every operation's contract test is in before any boundary test is.
  /// The result keeps the order of the document.
  GeneratedSelection select({Set<TestCategory>? categories, int cap = defaultCap}) {
    final wanted = categories ?? TestCategory.values.toSet();
    final eligible = [for (final c in cases) if (wanted.contains(c.category)) c];
    if (eligible.length <= cap) return GeneratedSelection(eligible, 0);
    final chosen = <GeneratedCase>{};
    for (final category in const [TestCategory.contract, TestCategory.auth, TestCategory.negative, TestCategory.boundary]) {
      for (final c in eligible) {
        if (chosen.length >= cap) break;
        if (c.category == category) chosen.add(c);
      }
    }
    return GeneratedSelection([for (final c in eligible) if (chosen.contains(c)) c], eligible.length - chosen.length);
  }
}

/// The result of [GeneratedSuite.select].
final class GeneratedSelection {
  final List<GeneratedCase> cases;

  /// Eligible cases left out because of the limit.
  final int skipped;
  const GeneratedSelection(this.cases, this.skipped);

  int count(TestCategory category) => cases.where((c) => c.category == category).length;

  int get changesDataCount => cases.where((c) => c.changesData).length;
}
