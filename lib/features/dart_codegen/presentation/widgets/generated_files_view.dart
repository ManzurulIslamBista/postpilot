import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/utils/generated_files_writer.dart';
import '../../../../core/widgets/code_block.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../workplace/presentation/view_models/workplace_view_model.dart';
import '../../domain/entities/generated_file.dart';
import 'generated_files_save.dart';

/// A generated project as a file list beside the selected file's code, with
/// "Copy all" and (on desktop) "Save to folder". Used by every generator that
/// produces more than one file.
class GeneratedFilesView extends StatefulWidget {
  final List<GeneratedFile> files;
  final String emptyTitle;
  final String emptyMessage;

  const GeneratedFilesView({
    super.key,
    required this.files,
    this.emptyTitle = 'Nothing generated yet',
    this.emptyMessage = '',
  });

  @override
  State<GeneratedFilesView> createState() => _GeneratedFilesViewState();
}

class _GeneratedFilesViewState extends State<GeneratedFilesView> {
  int _selected = 0;

  @override
  void didUpdateWidget(covariant GeneratedFilesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected >= widget.files.length) _selected = 0;
  }

  String get _everything => widget.files.map((f) => '// ===== ${f.path} =====\n${f.content}').join('\n\n');

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _everything));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${widget.files.length} files')));
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final workplaces = context.read<WorkplaceViewModel>();
    final folder = await workplaces.pickFolder();
    if (folder == null || !mounted) return;
    try {
      // Never replaces anything on its own: it asks first, and the result lists what was written and what was kept.
      final result = await saveGeneratedFiles(context, folder, widget.files);
      if (result == null || !mounted) return;
      await showWriteResult(context, folder, result);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't write the files: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    if (files.isEmpty) {
      return EmptyHint(icon: Icons.code, title: widget.emptyTitle, message: widget.emptyMessage);
    }
    final colors = context.colors;
    final canSave = canWriteFilesToFolder && context.read<WorkplaceViewModel>().canBrowseFolders;
    final selected = files[_selected.clamp(0, files.length - 1)];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final list = ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, i) {
            final f = files[i];
            final active = i == _selected;
            return InkWell(
              onTap: () => setState(() => _selected = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                color: active ? colors.mainAccent.withValues(alpha: 0.12) : null,
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, size: 14, color: active ? colors.mainAccent : colors.secondaryText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: f.path,
                        child: Text(
                          f.name,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.caption.copyWith(
                            color: active ? colors.primaryText : colors.secondaryText,
                            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
        final code = CodeBlock(
          key: ValueKey(selected.path),
          text: selected.content,
          label: selected.path,
        );
        final toolbar = Row(
          children: [
            Text('${files.length} files', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
            const Spacer(),
            TextButton.icon(onPressed: _copyAll, icon: const Icon(Icons.copy_all_outlined, size: 16), label: const Text('Copy all')),
            if (canSave)
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_alt, size: 16),
                label: const Text('Save to folder…'),
              ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            toolbar,
            const SizedBox(height: 8),
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        Container(
                          width: 210,
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: list,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: code),
                      ],
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 120,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: colors.border),
                            ),
                            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: list),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: code),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
