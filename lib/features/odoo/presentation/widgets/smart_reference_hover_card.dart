import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/services/smart_references.dart';

/// The card shown while hovering a `{{xmlid:...}}` or `{{ref:...}}` token in a request: what the token asks for and that
/// the id is looked up on the Odoo server when the request is sent. A badly written token says what is wrong with it.
/// Display only; it never takes the pointer.
class SmartReferenceHoverCard extends StatelessWidget {
  /// The token's inner text, `xmlid:base.main_company`.
  final String keyText;
  const SmartReferenceHoverCard({super.key, required this.keyText});

  static const width = 340.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final problem = SmartReferences.problemWith(keyText);
    final reference = SmartReference.tryParse(keyText);
    final accent = problem == null ? colors.syntaxKeyword : colors.statusError;
    final what = reference == null
        ? null
        : reference.kind == SmartReferenceKind.xmlId
            ? 'The id of the record with the XML-ID ${reference.module}.${reference.xmlName}.'
            : 'The id of the ${reference.model} record named "${reference.recordName}".';
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: width),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(12),
          opacity: 0.94,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: DefaultTextStyle(
            style: context.textStyles.body,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text('{{$keyText}}', overflow: TextOverflow.ellipsis, style: context.textStyles.mono.copyWith(color: accent, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accent.withValues(alpha: 0.4)),
                      ),
                      child: Text(problem == null ? 'Odoo reference' : 'Not valid', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  problem ??
                      '$what Looked up on the Odoo server this request goes to when it is sent, and remembered for ten minutes. '
                          'If it cannot be found, the request is not sent.',
                  style: context.textStyles.caption.copyWith(color: problem == null ? colors.secondaryText : colors.statusError, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
