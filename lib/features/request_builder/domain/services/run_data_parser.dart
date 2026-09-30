import 'dart:convert';
import 'package:csv/csv.dart';
import '../../../../core/constants/app_constants.dart';
import 'collection_run_options.dart';

/// The rows a data-driven run iterates over, or why the pasted text can't be
/// used ([error] is set and [rows] empty).
final class RunData {
  final List<Map<String, String>> rows;
  final List<String> columns;
  final String? error;

  const RunData({this.rows = const [], this.columns = const []}) : error = null;

  const RunData.invalid(String this.error)
      : rows = const [],
        columns = const [];

  static const empty = RunData();
}

/// Reads a run's data: a JSON array of objects (a lone object counts as one
/// row), or delimited text with a header row — comma, semicolon, tab or pipe,
/// picked from the header line so text pasted from a spreadsheet works. Every
/// value is a string; a row only holds the keys it actually has, so a missing
/// one falls through to the normal variable scopes.
final class RunDataParser {
  const RunDataParser();

  /// Blank text is [RunData.empty]: no data, not an error.
  RunData parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return RunData.empty;
    return trimmed.startsWith('[') || trimmed.startsWith('{') ? _fromJson(trimmed) : _fromCsv(text);
  }

  RunData _fromJson(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return RunData.invalid('Invalid JSON: ${e.message}');
    }
    final items = decoded is List ? decoded : (decoded is Map ? [decoded] : null);
    if (items == null) return const RunData.invalid('JSON data must be an array of objects');

    final rows = <Map<String, String>>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) return RunData.invalid('Item ${i + 1} of the JSON array is not an object');
      rows.add({
        for (final entry in item.entries)
          if ('${entry.key}'.isNotEmpty) '${entry.key}': _text(entry.value),
      });
    }
    return _validated(rows, <String>{for (final row in rows) ...row.keys}.toList());
  }

  RunData _fromCsv(String text) {
    final table = Csv(fieldDelimiter: _delimiterOf(text), autoDetect: false).decode(text);
    if (table.length < 2) return const RunData.invalid('CSV needs a header row and at least one row of data');

    final header = [for (final cell in table.first) '$cell'.trim()];
    final seen = <String>{};
    for (final name in header.where((name) => name.isNotEmpty)) {
      if (!seen.add(name)) return RunData.invalid('Column "$name" appears more than once');
    }
    final rows = [
      for (final line in table.skip(1))
        {
          for (var i = 0; i < header.length && i < line.length; i++)
            if (header[i].isNotEmpty) header[i]: '${line[i]}',
        },
    ];
    return _validated(rows, seen.toList());
  }

  RunData _validated(List<Map<String, String>> rows, List<String> columns) {
    for (final column in columns) {
      if (!_isReferenceable(column)) {
        return RunData.invalid('Column "$column" can\'t be used as a variable: use letters, digits, _ - . or \$ only');
      }
    }
    if (rows.isEmpty) return const RunData.invalid('The data has no rows');
    if (rows.length > CollectionRunOptions.maxIterations) {
      return RunData.invalid(
        'The data has ${rows.length} rows; a run allows at most ${CollectionRunOptions.maxIterations} iterations',
      );
    }
    return RunData(rows: rows, columns: columns);
  }

  /// The resolver only substitutes names its own `{{name}}` pattern matches
  /// whole, so any other column could never be referenced.
  bool _isReferenceable(String name) {
    final token = '{{$name}}';
    return AppConstants.variablePattern.matchAsPrefix(token)?.end == token.length;
  }

  String _delimiterOf(String text) {
    final headerLine = text.split(RegExp(r'\r?\n')).firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    var best = ',';
    var bestCount = 0;
    for (final candidate in const [',', '\t', ';', '|']) {
      final count = candidate.allMatches(headerLine).length;
      if (count > bestCount) {
        best = candidate;
        bestCount = count;
      }
    }
    return best;
  }

  String _text(Object? value) => switch (value) {
        null => '',
        String text => text,
        num() || bool() => '$value',
        _ => jsonEncode(value),
      };
}
