import 'package:flutter/material.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/widgets/code_block.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/services/bug_report_builder.dart';
import '../view_models/response_tools_view_model.dart';

/// A Markdown write-up of this request and response for an issue, a pull
/// request or a chat. Credentials are masked before it is shown.
class ShareTab extends StatefulWidget {
  final ResponseToolsViewModel viewModel;
  const ShareTab({super.key, required this.viewModel});

  @override
  State<ShareTab> createState() => _ShareTabState();
}

class _ShareTabState extends State<ShareTab> {
  final _note = TextEditingController();
  bool _headers = true;
  bool _requestBody = true;
  bool _responseBody = true;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _markdown() {
    final vm = widget.viewModel;
    final r = vm.data.response;
    final request = vm.request;
    return BugReportBuilder.build(
      method: request?.method.label ?? 'GET',
      url: request?.url ?? vm.data.requestName,
      requestHeaders: !_headers || request == null
          ? const {}
          : {for (final h in request.headers) if (h.enabled && h.key.isNotEmpty) h.key: h.value},
      requestBody: !_requestBody || request == null
          ? null
          : (request.body.type == BodyType.graphql ? request.body.graphqlQuery : request.body.rawText),
      statusCode: r.statusCode,
      statusText: r.statusMessage,
      durationMs: r.duration.inMilliseconds,
      sizeBytes: r.sizeBytes,
      responseHeaders: _headers ? r.headers : const {},
      responseBody: _responseBody ? vm.data.bodyText : null,
      note: _note.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final markdown = _markdown();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoBanner(
            kind: BannerKind.success,
            message: 'Passwords, tokens, API keys, Authorization headers and secrets inside bodies are masked automatically.',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'What went wrong? (optional)', prefixIcon: Icon(Icons.edit_note, size: 20)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(label: const Text('Headers'), selected: _headers, onSelected: (v) => setState(() => _headers = v)),
              FilterChip(label: const Text('Request body'), selected: _requestBody, onSelected: (v) => setState(() => _requestBody = v)),
              FilterChip(label: const Text('Response body'), selected: _responseBody, onSelected: (v) => setState(() => _responseBody = v)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: CodeBlock(text: markdown, label: 'Markdown', copyMessage: 'Copied', wrap: true)),
        ],
      ),
    );
  }
}
