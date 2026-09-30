import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/response_example_entity.dart';
import '../view_models/response_examples_view_model.dart';

class ResponseExamplesTab extends StatelessWidget {
  final int? selectedId;
  final ValueChanged<ResponseExampleEntity> onSelect;

  const ResponseExamplesTab({super.key, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ResponseExamplesViewModel>();
    if (vm.examples.isEmpty) {
      return Center(child: Text('No saved examples yet', style: context.textStyles.caption));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: vm.examples.length,
      itemBuilder: (context, index) {
        final example = vm.examples[index];
        return _ExampleTile(
          example: example,
          selected: example.id == selectedId,
          onTap: () {
            onSelect(example);
            DefaultTabController.of(context).animateTo(0);
          },
          onDelete: () => _delete(context, vm, example),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, ResponseExamplesViewModel vm, ResponseExampleEntity example) async {
    final confirmed =
        await showConfirmDialog(context, title: 'Delete example', message: 'Delete "${example.name}"?');
    if (confirmed) await vm.delete(example.id);
  }
}

class _ExampleTile extends StatelessWidget {
  final ResponseExampleEntity example;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ExampleTile({required this.example, required this.selected, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final statusColor = example.isSuccess ? context.colors.statusSuccess : context.colors.statusError;
    return ListTile(
      dense: true,
      selected: selected,
      leading: SizedBox(
        width: 36,
        child: Text(
          '${example.statusCode}',
          style: context.textStyles.body.copyWith(color: statusColor, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(example.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(formatExampleTimestamp(example.savedAt), style: context.textStyles.caption),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        tooltip: 'Delete example',
        onPressed: onDelete,
      ),
      onTap: onTap,
    );
  }
}

/// Status line shown in place of the live status/time/size row while a saved
/// example is being viewed.
class ResponseExampleSummary extends StatelessWidget {
  final ResponseExampleEntity example;
  final VoidCallback onClose;

  const ResponseExampleSummary({super.key, required this.example, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final statusColor = example.isSuccess ? context.colors.statusSuccess : context.colors.statusError;
    return Wrap(
      spacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${example.statusCode}',
            style: context.textStyles.body.copyWith(color: statusColor, fontWeight: FontWeight.bold)),
        Text('Example: ${example.name}', style: context.textStyles.body),
        Text('saved ${formatExampleTimestamp(example.savedAt)}', style: context.textStyles.caption),
        TextButton.icon(
          onPressed: onClose,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: context.textStyles.caption),
          icon: const Icon(Icons.arrow_back, size: 14),
          label: const Text('Back to live response'),
        ),
      ],
    );
  }
}

String formatExampleTimestamp(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
