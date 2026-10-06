import 'dart:convert';
import '../entities/odoo_model_info.dart';

/// Putting a field of a model into a JSON body that is being typed: the text for the field with a value of its type to
/// start from, and where it goes (a comma where one is needed).
abstract final class OdooSnippets {
  /// `"name": ""`, `"is_company": false`, `"state": "draft"`: [f] with an example value to replace. A many2one starts
  /// from `0`, an id that is never a record, so it cannot be sent by mistake.
  static String fieldSnippet(OdooField f) {
    final value = switch (f.type) {
      'integer' || 'many2one' || 'many2one_reference' => '0',
      'float' || 'monetary' => '0.0',
      'boolean' => 'false',
      'one2many' || 'many2many' => '[]',
      'selection' when f.selection.isNotEmpty => jsonEncode(f.selection.first.$1),
      'date' => '"YYYY-MM-DD"',
      'datetime' => '"YYYY-MM-DD HH:MM:SS"',
      _ => '""',
    };
    return '${jsonEncode(f.name)}: $value';
  }

  /// [text] with [snippet] put where the selection [start]..[end] is, with a comma before or after it when the
  /// neighbouring text is another entry. Returns the new text and where the cursor goes (after the snippet).
  static ({String text, int cursor}) insert(String text, int start, int end, String snippet) {
    if (text.trim().isEmpty) {
      final body = '{\n  $snippet\n}';
      return (text: body, cursor: body.length - 2);
    }
    final from = start.clamp(0, text.length);
    final to = end.clamp(from, text.length);
    final before = text.substring(0, from).trimRight();
    final after = text.substring(to).trimLeft();
    // The text before ends an entry (a string, a number, true/false/null, a list or an object), so another one follows a comma.
    final needsLeadingComma = RegExp(r'["\]}\del]$').hasMatch(before);
    final needsTrailingComma = after.startsWith('"');
    final insertion = '${needsLeadingComma ? ', ' : ''}$snippet${needsTrailingComma ? ', ' : ''}';
    final result = text.replaceRange(from, to, insertion);
    return (text: result, cursor: from + insertion.length);
  }
}
