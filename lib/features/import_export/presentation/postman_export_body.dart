import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../request_builder/domain/services/importers/postman_collection_exporter.dart';

/// The exported collection [json] with the choice to redact its secrets (on by default).
///
/// The file holds bearer tokens, passwords, API keys and the like in plain text. Redacting replaces each
/// of them with a `{{variable}}` placeholder, so the file can be shared without them and the person who
/// imports it only has to fill in the variables.
class PostmanExportBody extends StatefulWidget {
  final String json;
  const PostmanExportBody({super.key, required this.json});

  @override
  State<PostmanExportBody> createState() => _PostmanExportBodyState();
}

class _PostmanExportBodyState extends State<PostmanExportBody> {
  static const _previewLimit = 40000;

  bool _redact = true;
  late String _redacted = PostmanCollectionExporter.redact(widget.json);

  @override
  void didUpdateWidget(PostmanExportBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.json != widget.json) _redacted = PostmanCollectionExporter.redact(widget.json);
  }

  String get _shown => _redact ? _redacted : widget.json;

  void _copy() {
    Clipboard.setData(ClipboardData(text: _shown));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exported to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final text = _shown.length > _previewLimit
        ? '${_shown.substring(0, _previewLimit)}\n... preview shortened; Copy gives everything.'
        : _shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoBanner(
          kind: _redact ? BannerKind.info : BannerKind.warning,
          title: _redact ? 'Secrets are replaced' : 'Secrets are written in plain text',
          message: _redact
              ? 'Tokens, passwords and API keys are replaced by {{variables}} such as {{bearerToken}}. '
                  'Fill them in after importing the collection.'
              : 'Tokens, passwords, API keys and secret variable values are in this file as they are. '
                  'Check it before you share it.',
        ),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _redact,
                onChanged: (value) => setState(() => _redact = value ?? true),
                title: const Text('Redact secrets'),
              ),
            ),
            IconButton(icon: const Icon(Icons.copy, size: 18), tooltip: 'Copy', onPressed: _copy),
          ],
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText(text, style: context.textStyles.mono.copyWith(fontSize: 12)),
          ),
        ),
      ],
    );
  }
}
