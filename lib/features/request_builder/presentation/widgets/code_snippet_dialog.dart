import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/services/code_generators/code_generator.dart';
import '../../domain/services/code_generators/code_generator_registry.dart';
import '../view_models/request_builder_view_model.dart';

class CodeSnippetDialog extends StatefulWidget {
  final RequestBuilderViewModel viewModel;
  const CodeSnippetDialog({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, RequestBuilderViewModel viewModel) =>
      showDialog(context: context, builder: (_) => CodeSnippetDialog(viewModel: viewModel));

  @override
  State<CodeSnippetDialog> createState() => _CodeSnippetDialogState();
}

class _CodeSnippetDialogState extends State<CodeSnippetDialog> {
  CodeGenerator _generator = CodeGeneratorRegistry.all.first;
  String _snippet = '';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    var snippet = '';
    String? error;
    try {
      snippet = await widget.viewModel.generateCodeSnippet(_generator);
    } catch (e) {
      error = "Couldn't generate this snippet. Check the URL and body, and that every "
          '{{variable}} they use is defined and enabled.\n\n$e';
    }
    if (mounted) setState(() { _snippet = snippet; _error = error; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 600,
        height: 480,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Code', style: context.textStyles.heading),
                  const Spacer(),
                  DropdownButton<CodeGenerator>(
                    value: _generator,
                    items: [
                      for (final g in CodeGeneratorRegistry.all) DropdownMenuItem(value: g, child: Text(g.label)),
                    ],
                    onChanged: (g) {
                      if (g == null) return;
                      setState(() => _generator = g);
                      _load();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy',
                    onPressed: _error == null ? () => Clipboard.setData(ClipboardData(text: _snippet)) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: SelectableText(
                          _error ?? _snippet,
                          style: _error == null
                              ? context.textStyles.mono
                              : context.textStyles.mono.copyWith(color: context.colors.statusError),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
