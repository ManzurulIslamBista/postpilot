import '../../../scripting/domain/entities/assertion_entity.dart';

/// How a list of suggestions is grouped on screen, in this order.
enum SuggestionGroup {
  basics('Basics'),
  structure('Body structure'),
  fields('Required fields'),
  arrays('Arrays'),
  allowedValues('Allowed values'),
  formats('Formats'),
  exact('Exact values');

  final String label;
  const SuggestionGroup(this.label);
}

/// How likely a check is to keep passing while the API has not changed: [high] holds on any healthy answer,
/// [medium] relies on what this one response happened to contain, [low] on values that may be data, not contract.
enum SuggestionConfidence {
  high('High'),
  medium('Medium'),
  low('Low');

  final String label;
  const SuggestionConfidence(this.label);
}

/// One check the app proposes for a request, with the words that explain it. Nothing is added to the request
/// until the person ticks it and chooses to add it.
final class TestSuggestion {
  /// Stable for the same response, so a ticked row stays ticked when the list is rebuilt.
  final String id;
  final SuggestionGroup group;

  /// What the check says in plain words: `status is 200`, `body.items is a non-empty array`.
  final String label;

  /// Why it is proposed, or what to watch out for.
  final String? detail;
  final SuggestionConfidence confidence;

  /// The check itself. It has a session id of its own; the one that is stored gets a fresh one.
  final AssertionEntity assertion;

  /// Ticked when the list first shows.
  final bool recommended;

  const TestSuggestion({
    required this.id,
    required this.group,
    required this.label,
    required this.confidence,
    required this.assertion,
    this.detail,
    this.recommended = false,
  });
}

/// A field a second response showed to change by itself, shown so the person sees what was left out.
final class VolatileField {
  /// `body.items[*].id`
  final String label;

  /// Why: it changed between the two responses, or looks like an id or a timestamp.
  final String reason;
  const VolatileField(this.label, this.reason);
}

/// Everything the engine says about one response (or two, after the stability probe).
final class SuggestionResult {
  final List<TestSuggestion> suggestions;

  /// Things the person should know: the body is not JSON, the analysis stopped early, the second response was ignored.
  final List<String> notes;

  /// Fields kept out of the exact-value checks because they change by themselves.
  final List<VolatileField> volatile;

  /// Whether a second response was compared.
  final bool probed;

  const SuggestionResult({
    required this.suggestions,
    this.notes = const [],
    this.volatile = const [],
    this.probed = false,
  });

  static const empty = SuggestionResult(suggestions: []);
}
