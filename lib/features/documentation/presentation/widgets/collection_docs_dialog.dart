import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/collection_docs_view_model.dart';
import 'simple_markdown.dart';

/// The generated documentation of a collection: a rendered preview with
/// buttons to copy the Markdown or save it as .md or .html.
class CollectionDocsDialog extends StatefulWidget {
  final int collectionId;
  final String collectionName;

  const CollectionDocsDialog({super.key, required this.collectionId, required this.collectionName});

  static Future<void> show(BuildContext context, {required int collectionId, required String collectionName}) =>
      showDialog(
        context: context,
        builder: (_) => CollectionDocsDialog(collectionId: collectionId, collectionName: collectionName),
      );

  @override
  State<CollectionDocsDialog> createState() => _CollectionDocsDialogState();
}

class _CollectionDocsDialogState extends State<CollectionDocsDialog> {
  late final CollectionDocsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<CollectionDocsViewModel>();
    _viewModel.load(widget.collectionId);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _copy(CollectionDocsViewModel vm) async {
    await Clipboard.setData(ClipboardData(text: vm.markdown));
    if (mounted) _showMessage('Markdown copied to the clipboard');
  }

  Future<void> _save(Future<String> Function() save) async {
    final message = await save();
    if (mounted) _showMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CollectionDocsViewModel>.value(
      value: _viewModel,
      child: Consumer<CollectionDocsViewModel>(
        builder: (context, vm, _) => Dialog(
          child: SizedBox(
            width: 760,
            height: 620,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Documentation · ${widget.collectionName}',
                          style: context.textStyles.heading,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: vm.isReady ? () => _copy(vm) : null,
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Markdown'),
                        ),
                        OutlinedButton.icon(
                          onPressed: vm.isReady ? () => _save(vm.saveMarkdown) : null,
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Download .md'),
                        ),
                        OutlinedButton.icon(
                          onPressed: vm.isReady ? () => _save(vm.saveHtml) : null,
                          icon: const Icon(Icons.html, size: 16),
                          label: const Text('Download .html'),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _content(context, vm)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, CollectionDocsViewModel vm) {
    if (vm.isLoading) return const Center(child: CircularProgressIndicator());
    final error = vm.error;
    if (error != null) {
      return Center(child: Text(error, style: TextStyle(color: context.colors.statusError)));
    }
    return SimpleMarkdown(data: vm.markdown, scrollable: true, padding: const EdgeInsets.all(16));
  }
}
