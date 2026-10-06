import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/code_block.dart';
import '../../../core/widgets/info_banner.dart';
import '../../response_tools/presentation/view_models/response_tools_view_model.dart';
import '../../scripting/domain/entities/assertion_entity.dart';
import '../data/ai_client.dart';
import '../domain/ai_tasks.dart';
import 'ai_key_setup.dart';

/// "Ask AI" in the response tools: explain this response, or propose tests for it.
class AiTab extends StatefulWidget {
  final ResponseToolsViewModel viewModel;
  const AiTab({super.key, required this.viewModel});

  @override
  State<AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<AiTab> {
  final _client = locator<AiClient>();
  final _question = TextEditingController();
  bool? _hasKey;
  bool _busy = false;
  String? _answer;
  String? _error;
  List<AssertionEntity> _suggested = const [];
  bool _showSent = false;

  @override
  void initState() {
    super.initState();
    _refreshKey();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _refreshKey() async {
    final has = await _client.hasKey;
    if (mounted) setState(() => _hasKey = has);
  }

  String get _input {
    final vm = widget.viewModel;
    final r = vm.data.response;
    // The request as it was sent, masked after resolution: what leaves the app is exactly what "Show what is sent" shows.
    return AiTasks.explainInput(
      method: vm.requestMethod,
      url: vm.requestUrl,
      statusCode: r.statusCode,
      statusText: r.statusMessage,
      requestHeaders: vm.requestHeaders,
      requestBody: vm.requestBodyText,
      responseHeaders: r.headers,
      responseBody: vm.data.bodyText,
      question: _question.text,
      secretValues: vm.secretValues,
    );
  }

  Future<void> _ask({required bool tests}) async {
    setState(() {
      _busy = true;
      _error = null;
      _answer = null;
      _suggested = const [];
    });
    try {
      final reply = await _client.complete(system: tests ? AiTasks.testsSystem : AiTasks.explainSystem, user: _input, maxTokens: tests ? 1024 : 1500);
      if (tests) {
        final parsed = AiTasks.parseAssertions(reply);
        if (parsed.isEmpty) {
          _error = "The model's answer could not be read as tests. Try again.";
        } else {
          _suggested = parsed;
        }
      } else {
        _answer = reply;
      }
    } on AiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addTests() async {
    for (final a in _suggested) {
      await widget.viewModel.addAssertion(a);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${_suggested.length} tests (see the Tests tab)')));
      setState(() => _suggested = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (_hasKey == null) return const Center(child: CircularProgressIndicator());
    if (!_hasKey!) {
      return ListView(padding: const EdgeInsets.all(16), children: [AiKeySetup(hasKey: false, onChanged: _refreshKey)]);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _question,
          decoration: const InputDecoration(labelText: 'Ask something about this response (optional)', hintText: 'Why is this 403? What does total_due mean?', prefixIcon: Icon(Icons.chat_bubble_outline, size: 18)),
          onSubmitted: (_) => _ask(tests: false),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton(onPressed: _busy ? null : () => _ask(tests: false), child: BusyLabel(busy: _busy, icon: Icons.auto_awesome, label: 'Explain this response', busyLabel: 'Thinking…')),
            OutlinedButton.icon(onPressed: _busy ? null : () => _ask(tests: true), icon: const Icon(Icons.rule, size: 16), label: const Text('Suggest tests')),
            TextButton.icon(onPressed: () => setState(() => _showSent = !_showSent), icon: Icon(_showSent ? Icons.visibility_off : Icons.visibility, size: 16), label: Text(_showSent ? 'Hide what is sent' : 'Show what is sent')),
          ],
        ),
        if (_showSent) ...[
          const SizedBox(height: 8),
          SizedBox(height: 180, child: CodeBlock(text: _input, label: 'Sent to Anthropic (credentials masked)', wrap: true)),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: InfoBanner(kind: BannerKind.error, message: _error!)),
        if (_answer != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
            child: SelectableText(_answer!, style: context.textStyles.body.copyWith(height: 1.45)),
          ),
        ],
        if (_suggested.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
            child: Column(
              children: [
                for (final a in _suggested) ListTile(dense: true, leading: Icon(Icons.rule, size: 18, color: colors.mainAccent), title: Text(a.name)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _addTests, icon: const Icon(Icons.add_task, size: 16), label: Text('Add ${_suggested.length} tests'))),
        ],
        const SizedBox(height: 16),
        Text('AI can be wrong. Check its answers before relying on them.', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
      ],
    );
  }
}
