import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../domain/services/json_schema_tools.dart';
import '../view_models/response_tools_view_model.dart';

/// Checks the response against a JSON Schema (paste an OpenAPI response
/// schema, or infer one from real responses), and can keep the schema as a
/// test so every future send is checked.
class SchemaTab extends StatefulWidget {
  final ResponseToolsViewModel viewModel;
  const SchemaTab({super.key, required this.viewModel});

  @override
  State<SchemaTab> createState() => _SchemaTabState();
}

class _SchemaTabState extends State<SchemaTab> {
  final _schema = TextEditingController();
  List<SchemaViolation>? _violations;
  String? _error;

  @override
  void dispose() {
    _schema.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _parsed() {
    try {
      final v = jsonDecode(_schema.text);
      if (v is Map<String, dynamic>) return v;
      _error = 'The schema must be a JSON object.';
    } on FormatException catch (e) {
      _error = 'The schema is not valid JSON: ${e.message}';
    }
    return null;
  }

  void _validate() {
    setState(() {
      _error = null;
      final schema = _parsed();
      _violations = schema == null ? null : JsonSchemaTools.validate(schema, widget.viewModel.data.json);
    });
  }

  void _infer() {
    final vm = widget.viewModel;
    final samples = <Object?>[vm.data.json];
    for (final s in vm.compareSources) {
      try {
        samples.add(jsonDecode(s.body));
      } on FormatException {
        // A body that is not JSON cannot inform the schema.
      }
    }
    setState(() {
      _schema.text = JsonSchemaTools.encode(JsonSchemaTools.infer(samples));
      _error = null;
      _violations = null;
    });
  }

  Future<void> _saveAsTest() async {
    if (_parsed() == null) {
      setState(() {});
      return;
    }
    final compact = jsonEncode(jsonDecode(_schema.text));
    await widget.viewModel.addAssertion(AssertionEntity(type: AssertionType.jsonSchema, expected: compact));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schema saved as a test (see the Tests tab)')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    if (!vm.data.isJson) {
      return const EmptyHint(
        icon: Icons.rule,
        title: 'This response is not JSON',
        message: 'Schema checks need a JSON body.',
      );
    }
    final colors = context.colors;
    final violations = _violations;
    final samples = 1 + vm.compareSources.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) {
          final editor = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: _infer,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: Text('Infer from $samples ${samples == 1 ? 'response' : 'responses'}'),
                  ),
                  FilledButton.icon(onPressed: _validate, icon: const Icon(Icons.check_circle_outline, size: 16), label: const Text('Validate')),
                  OutlinedButton.icon(onPressed: _saveAsTest, icon: const Icon(Icons.save_outlined, size: 16), label: const Text('Save as test')),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _schema,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: context.textStyles.mono,
                  decoration: const InputDecoration(
                    hintText: 'Paste a JSON Schema (or an OpenAPI response schema with its components), '
                        'or press "Infer" to build one from the real responses.',
                  ),
                ),
              ),
            ],
          );
          final results = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) InfoBanner(kind: BannerKind.error, message: _error!),
              if (violations != null && violations.isEmpty)
                const InfoBanner(kind: BannerKind.success, title: 'Valid', message: 'The response matches the schema.'),
              if (violations != null && violations.isNotEmpty) ...[
                InfoBanner(
                  kind: BannerKind.error,
                  title: '${violations.length} ${violations.length == 1 ? 'problem' : 'problems'}',
                  message: 'The response does not match the schema:',
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.appBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      itemCount: violations.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: SelectableText.rich(TextSpan(children: [
                          TextSpan(text: '${violations[i].path}  ', style: context.textStyles.mono.copyWith(color: colors.syntaxKey, fontWeight: FontWeight.w600)),
                          TextSpan(text: violations[i].message, style: context.textStyles.body),
                        ])),
                      ),
                    ),
                  ),
                ),
              ],
              if (violations == null && _error == null)
                const Expanded(
                  child: EmptyHint(
                    icon: Icons.rule,
                    title: 'Validate against a schema',
                    message: 'Results appear here. "Save as test" keeps the schema in the Tests tab so every send is checked.',
                  ),
                ),
            ],
          );
          return c.maxWidth >= 720
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: editor), const SizedBox(width: 14), Expanded(child: results)])
              : Column(children: [Expanded(flex: 3, child: editor), const SizedBox(height: 10), Expanded(flex: 2, child: results)]);
        },
      ),
    );
  }
}
