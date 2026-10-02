import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../shell/presentation/shell_view_model.dart';
import '../domain/starter_templates.dart';
import '../domain/usecases/add_starter_template_usecase.dart';

/// A gallery of ready-made collections: pick one and it is in the sidebar,
/// with its environment selected, ready to send.
class TemplatesDialog extends StatefulWidget {
  const TemplatesDialog({super.key});

  static Future<void> show(BuildContext context) => ToolDialog.show(context, (_) => const TemplatesDialog());

  @override
  State<TemplatesDialog> createState() => _TemplatesDialogState();
}

class _TemplatesDialogState extends State<TemplatesDialog> {
  final _templates = StarterTemplates.all();
  String? _adding;

  Future<void> _add(StarterTemplate template) async {
    setState(() => _adding = template.id);
    final messenger = ScaffoldMessenger.of(context);
    final collections = context.read<CollectionsViewModel>();
    final shell = context.read<ShellViewModel>();
    try {
      final added = await locator<AddStarterTemplateUseCase>()(template);
      collections.expandCollection(added.collectionId);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('Added "${template.title}": ${added.requests} requests${added.environmentId != null ? ' and an environment' : ''}')));
      final first = await collections.firstRequestId(added.collectionId);
      if (first != null) shell.selectRequest(first);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't add the template: $e")));
      if (mounted) setState(() => _adding = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ToolDialog(
      icon: Icons.auto_awesome_mosaic_outlined,
      title: 'Starter templates',
      subtitle: 'Add a ready-made collection and try it straight away',
      width: 820,
      height: 600,
      child: LayoutBuilder(
        builder: (context, c) {
          final columns = c.maxWidth >= 700 ? 2 : 1;
          return GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns == 2 ? 2.05 : 2.6,
            children: [
              for (final t in _templates)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.border)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(color: colors.mainAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                            child: Icon(t.icon, size: 18, color: colors.mainAccent),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(t.title, style: context.textStyles.heading, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(child: Text(t.description, style: context.textStyles.caption.copyWith(color: colors.secondaryText, height: 1.35), overflow: TextOverflow.fade)),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('${t.requestCount} requests', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                                for (final tag in t.tags.take(2))
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(10)),
                                    child: Text(tag, style: TextStyle(fontSize: 10.5, color: colors.secondaryText)),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _adding != null ? null : () => _add(t),
                            child: BusyLabel(busy: _adding == t.id, icon: Icons.add, label: 'Add', busyLabel: 'Adding…'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
