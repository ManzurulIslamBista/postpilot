import 'package:flutter/material.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../view_models/variable_scope.dart';
import '../json_syntax.dart' show maxHighlightedChars;

/// A text controller that draws each `{{variable}}` in colour: the accent when
/// the request can resolve it, the error colour when nothing defines it. The
/// text itself is untouched, so whatever reads [text] (the request, the code
/// generators) sees the raw `{{name}}`.
class VariableTextEditingController extends TextEditingController {
  VariableTextEditingController({super.text});

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
    for (final match in AppConstants.variablePattern.allMatches(text)) {
      if (match.start > cursor) spans.add(TextSpan(text: text.substring(cursor, match.start)));
      // Until the first load nothing is flagged as undefined.
      final defined = !scope.isLoaded || scope.isDefined(match[1]!);
      final color = defined ? colors.mainAccent : colors.statusError;
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
