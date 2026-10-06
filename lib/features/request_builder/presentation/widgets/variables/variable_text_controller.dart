import 'package:flutter/material.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/variable_resolver.dart';
import '../../../../odoo/domain/services/smart_references.dart';
import '../../view_models/variable_scope.dart';
import '../json_syntax.dart' show maxHighlightedChars;

/// A text controller that draws each `{{variable}}` in colour: the accent when
/// the request can resolve it, the error colour when nothing defines it. The
/// text itself is untouched, so whatever reads [text] (the request, the code
/// generators) sees the raw `{{name}}`.
class VariableTextEditingController extends TextEditingController {
  VariableTextEditingController({super.text});

  /// A `{{variable}}` (group 1) or an Odoo smart reference `{{xmlid:...}}` / `{{ref:...}}` (group 2), which is looked
  /// up on the server when the request is sent and is drawn in its own colour.
  static final tokenPattern = RegExp('${AppConstants.variablePattern.pattern}|${VariableResolver.smartTokenPattern.pattern}');

  VariableScope? _scope;

  /// What decides a token's colour. Set by the field that owns this controller
  /// once it can see the request's [VariableScope]; none means plain text.
  set scope(VariableScope? value) {
    if (identical(_scope, value)) return;
    _scope?.removeListener(notifyListeners);
    _scope = value;
    _scope?.addListener(notifyListeners);
    notifyListeners();
  }

  @override
  void dispose() {
    _scope?.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final text = this.text;
    final scope = _scope;
    final colors = Theme.of(context).extension<AppColors>();
    // Not while an IME composes (its underline must survive), and not for huge
    // bodies, where thousands of coloured spans cost more than they help.
    final composing = withComposing && value.isComposingRangeValid;
    if (scope == null || colors == null || composing || !text.contains('{{') || text.length > maxHighlightedChars) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in tokenPattern.allMatches(text)) {
      if (match.start > cursor) spans.add(TextSpan(text: text.substring(cursor, match.start)));
      // Until the first load nothing is flagged as undefined. A smart reference is never a variable: it is resolved
      // against the server at send time, so it has a colour of its own.
      final smart = match[1] == null;
      final defined = smart || !scope.isLoaded || scope.isDefined(match[1]!);
      final color = smart
          ? (SmartReferences.problemWith(match[2]!) == null ? colors.syntaxKeyword : colors.statusError)
          : (defined ? colors.mainAccent : colors.statusError);
      spans.add(
        TextSpan(
          text: match[0],
          style: TextStyle(color: color, fontWeight: FontWeight.w600, backgroundColor: color.withValues(alpha: 0.10)),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: style, children: spans);
  }
}
