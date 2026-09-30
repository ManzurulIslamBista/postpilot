import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/utils/file_download.dart';
import '../../../core/utils/safe_file_name.dart';
import '../domain/entities/collection_export_result.dart';
import 'view_models/export_collection_view_model.dart';

/// Shows one collection rendered as an OpenAPI 3.0 document or as a cURL
/// script, ready to copy or download.
class ExportCollectionDialog extends StatefulWidget {
  final int collectionId;
  final CollectionExportKind kind;

  const ExportCollectionDialog({super.key, required this.collectionId, required this.kind});

  static Future<void> showOpenApi(BuildContext context, {required int collectionId}) => _show(context, collectionId, CollectionExportKind.openApi);

  static Future<void> showCurlScript(BuildContext context, {required int collectionId}) =>
      _show(context, collectionId, CollectionExportKind.curlScript);

  static Future<void> _show(BuildContext context, int collectionId, CollectionExportKind kind) =>
      showDialog(context: context, builder: (_) => ExportCollectionDialog(collectionId: collectionId, kind: kind));

  @override
  State<ExportCollectionDialog> createState() => _ExportCollectionDialogState();
}

class _ExportCollectionDialogState extends State<ExportCollectionDialog> {
  static const _previewLimit = 40000;

  late final ExportCollectionViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<ExportCollectionViewModel>();
    _viewModel.export(widget.kind, widget.collectionId);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _copy(CollectionExportResult result) {
    Clipboard.setData(ClipboardData(text: result.text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exported to clipboard')));
  }

  Future<void> _download(CollectionExportResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    final base = sanitizeFileName(result.collectionName) ?? 'collection';
    try {
      final path = await downloadFile(
        fileName: '$base-${widget.kind.fileSuffix}.${widget.kind.fileExtension}',
        bytes: Uint8List.fromList(utf8.encode(result.text)),
        mimeType: widget.kind.mimeType,
      );
      messenger.showSnackBar(SnackBar(content: Text(path == null ? 'Download started' : 'Saved to $path')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't save file: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ExportCollectionViewModel>.value(
      value: _viewModel,
      child: Consumer<ExportCollectionViewModel>(
        builder: (context, vm, _) {
          final result = vm.result;
          return Dialog(
            child: SizedBox(
              width: 640,
              height: 520,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(widget.kind.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (result != null) ...[
                          IconButton(icon: const Icon(Icons.copy, size: 18), tooltip: 'Copy', onPressed: () => _copy(result)),
                          IconButton(icon: const Icon(Icons.download, size: 18), tooltip: 'Download', onPressed: () => _download(result)),
                        ],
                        IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    if (result != null) _Summary(result: result, kind: widget.kind),
                    const Divider(),
                    Expanded(child: _buildBody(context, vm, result)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, ExportCollectionViewModel vm, CollectionExportResult? result) {
    if (vm.error != null) return Text(vm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error));
    if (result == null) return const Center(child: CircularProgressIndicator());
    final text = result.text.length > _previewLimit
        ? '${result.text.substring(0, _previewLimit)}\n... preview shortened; Copy or Download gives everything.'
        : result.text;
    return SingleChildScrollView(child: SelectableText(text, style: context.textStyles.mono.copyWith(fontSize: 12)));
  }
}

class _Summary extends StatelessWidget {
  final CollectionExportResult result;
  final CollectionExportKind kind;
  const _Summary({required this.result, required this.kind});

  @override
  Widget build(BuildContext context) {
    final skipped = result.skipped == 0
        ? ''
        : kind == CollectionExportKind.openApi
            ? ' ${result.skipped} skipped (no URL, or the same method and path as another request).'
            : ' ${result.skipped} skipped (see the comments in the script).';
    final secrets = switch (kind) {
      CollectionExportKind.curlScript => ' Variable and secret values are written in plain text.',
      CollectionExportKind.openApi => ' Header, query and body values are written as examples, so check them for secrets before sharing.',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('${result.itemCount} requests exported.$skipped$secrets', style: context.textStyles.caption),
    );
  }
}
