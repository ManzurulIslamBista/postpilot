import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';

const browserUnavailableNote = 'Not available in the browser version';

/// Below this width the control no longer fits beside the text without
/// squeezing it to a sliver, so it goes under the text instead.
const _stackBelowWidth = 400.0;

/// One labelled setting: title and description on the left, the control on
/// the right, or under the text when [stacked] (a control too wide to share
/// the row) or the row is narrow. [unavailable] adds the browser note; the
/// caller disables the control itself. [note] is any other caveat, shown the
/// same way.
class SettingRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget control;
  final bool stacked;
  final bool unavailable;
  final String? note;

  const SettingRow({
    super.key,
    required this.title,
    required this.control,
    this.description,
    this.stacked = false,
    this.unavailable = false,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.textStyles.body),
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(description!, style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
          ),
        if (unavailable || note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              unavailable ? browserUnavailableNote : note!,
              style: context.textStyles.caption.copyWith(color: context.colors.mainAccent),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) => stacked || constraints.maxWidth < _stackBelowWidth
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [text, const SizedBox(height: 8), control],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [Expanded(child: text), const SizedBox(width: 16), control],
              ),
      ),
    );
  }
}
