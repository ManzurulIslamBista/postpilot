import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/code_block.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/services/dart_model_generator.dart';

/// JSON in, Dart classes out, live as the user types. Several responses of the
/// same endpoint can be pasted, separated by a line holding only `---`: the
/// classes then reflect which fields are optional.
class DartModelPane extends StatefulWidget {
  final String initialJson;
  final String initialName;

  const DartModelPane({super.key, this.initialJson = '', this.initialName = 'Root'});

  @override
  State<DartModelPane> createState() => _DartModelPaneState();
}

class _DartModelPaneState extends State<DartModelPane> {
  late final TextEditingController _json = TextEditingController(text: widget.initialJson);
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  DartModelStyle _style = DartModelStyle.plain;
  bool _detectDates = true;
  bool _allNullable = false;

  @override
  void dispose() {
    _json.dispose();
    _name.dispose();
    super.dispose();
  }

  DartModelResult _generate() {
    final samples = _json.text.split(RegExp(r'^\s*---\s*$', multiLine: true));
    return const DartModelGenerator().generate(
      samples,
      rootName: _name.text.trim().isEmpty ? 'Root' : _name.text.trim(),
      options: DartModelOptions(style: _style, detectDates: _detectDates, allNullable: _allNullable),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final result = _generate();
    final input = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Class name', prefixIcon: Icon(Icons.data_object, size: 18)),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<DartModelStyle>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [for (final s in DartModelStyle.values) ButtonSegment(value: s, label: Text(s.label, style: const TextStyle(fontSize: 12)))],
          selected: {_style},
          onSelectionChanged: (s) => setState(() => _style = s.first),
        ),
        const SizedBox(height: 4),
        Text(_style.description, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Detect dates'),
              selected: _detectDates,
              onSelected: (v) => setState(() => _detectDates = v),
            ),
            FilterChip(
              label: const Text('All fields optional'),
              selected: _allNullable,
              onSelected: (v) => setState(() => _allNullable = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _json,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: context.textStyles.mono,
            decoration: const InputDecoration(
              hintText: 'Paste a JSON response here.\n\nPaste several responses of the same endpoint, '
                  'separated by a line with ---, so optional fields are detected.',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
    final output = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final note in result.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InfoBanner(kind: result.classCount == 0 ? BannerKind.warning : BannerKind.info, message: note),
          ),
        Expanded(
          child: result.code.isEmpty
              ? const EmptyHint(
                  icon: Icons.code,
                  title: 'Your Dart classes appear here',
                  message: 'Paste JSON on the left. Nested objects and lists become their own classes.',
                )
              : CodeBlock(
                  text: result.code,
                  label: 'Dart · ${result.classCount} ${result.classCount == 1 ? 'class' : 'classes'}',
                ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 720
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(flex: 5, child: input), const SizedBox(width: 14), Expanded(flex: 6, child: output)],
              )
            : Column(
                children: [
                  Expanded(flex: 5, child: input),
                  const SizedBox(height: 12),
                  Expanded(flex: 6, child: output),
                ],
              ),
      ),
    );
  }
}
