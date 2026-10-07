import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/utils/generated_files_writer.dart';
import '../../domain/entities/generated_file.dart';
import '../../domain/services/file_change_plan.dart';

/// Writes [files] below [folder] without replacing anything on its own. Shared
/// files that already exist (the project's own `api_client.dart`) are kept; any
/// other existing file is replaced only if the user says so. Returns what
/// happened, or null when the user cancelled.
Future<WriteFilesResult?> saveGeneratedFiles(BuildContext context, String folder, List<GeneratedFile> files) async {
  final existing = await existingFilesInFolder(folder, [for (final f in files) f.path]);
  final shared = {for (final f in files) if (f.shared) f.path};
  final conflicts = [for (final path in existing) if (!shared.contains(path)) path];
  var overwrite = false;
  if (conflicts.isNotEmpty) {
    if (!context.mounted) return null;
    final choice = await confirmOverwrite(context, folder, conflicts);
    if (choice == null) return null;
    overwrite = choice;
  }
  return writeFilesToFolder(folder, {for (final f in files) f.path: f.content}, overwrite: overwrite, neverOverwrite: shared);
}

/// Asks what to do with [existing] files that the new ones would replace. `true`
/// replaces them, `false` keeps them and writes only the files that are new, null cancels.
Future<bool?> confirmOverwrite(BuildContext context, String folder, List<String> existing) => showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = context.colors;
        return AlertDialog(
          title: Text(existing.length == 1 ? '1 file already exists' : '${existing.length} files already exist'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'These are already in $folder. Replacing them loses any change you made to them.',
                  style: context.textStyles.body,
                ),
                const SizedBox(height: 10),
                _PathList(paths: existing, maxHeight: 180),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep them, write the rest')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.statusError),
              onPressed: () => Navigator.pop(context, true),
              child: Text(existing.length == 1 ? 'Replace it' : 'Replace ${existing.length} files'),
            ),
          ],
        );
      },
    );

/// Tells the user exactly what [saveGeneratedFiles] did: what is new, what was
/// replaced and what was left as it was.
Future<void> showWriteResult(BuildContext context, String folder, WriteFilesResult result) => showDialog<void>(
      context: context,
      builder: (context) {
        final colors = context.colors;
        final replaced = result.overwritten;
        final created = [for (final path in result.written) if (!replaced.contains(path)) path];
        return AlertDialog(
          title: Text(result.written.isEmpty ? 'Nothing was written' : 'Saved to $folder'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ResultSection(
                    icon: Icons.add_circle_outline,
                    color: colors.statusSuccess,
                    title: created.length == 1 ? '1 new file written' : '${created.length} new files written',
                    paths: created,
                  ),
                  _ResultSection(
                    icon: Icons.sync_alt,
                    color: colors.statusWarning,
                    title: replaced.length == 1 ? '1 file replaced' : '${replaced.length} files replaced',
                    paths: replaced,
                  ),
                  _ResultSection(
                    icon: Icons.block,
                    color: colors.secondaryText,
                    title: result.skipped.length == 1
                        ? '1 existing file kept as it was'
                        : '${result.skipped.length} existing files kept as they were',
                    paths: result.skipped,
                    note: 'If one of these is a base class the generated code builds on (api_client.dart, usecase.dart), '
                        'check that it still matches what the generated code expects.',
                  ),
                ],
              ),
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        );
      },
    );

class _ResultSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<String> paths;
  final String? note;

  const _ResultSection({required this.icon, required this.color, required this.title, required this.paths, this.note});

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700, color: color))),
            ],
          ),
          const SizedBox(height: 6),
          _PathList(paths: paths, maxHeight: 130),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
          ],
        ],
      ),
    );
  }
}

class _PathList extends StatelessWidget {
  final List<String> paths;
  final double maxHeight;
  const _PathList({required this.paths, required this.maxHeight});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.appBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      // Its own controller (primary: false): two of these in one dialog must not share the primary one.
      child: ListView(
        primary: false,
        shrinkWrap: true,
        padding: const EdgeInsets.all(8),
        children: [for (final path in paths) SelectableText(path, style: context.textStyles.mono)],
      ),
    );
  }
}

/// "Write changed files only": compares [files] with what [folder] holds, shows what each new or changed file would
/// look like as a diff, and after a yes writes just those. Files that are already identical are not touched, and a
/// shared file the project has (its own `api_client.dart`) is kept. Returns what was written, an empty result when
/// nothing needed writing, or null when the user cancelled.
Future<WriteFilesResult?> saveChangedGeneratedFiles(BuildContext context, String folder, List<GeneratedFile> files) async {
  final onDisk = await readFilesInFolder(folder, [for (final f in files) f.path]);
  final plan = FileChangePlan.compute(files, onDisk);
  if (!context.mounted) return null;
  final go = await showChangePreview(context, folder, plan);
  if (go != true) return plan.hasWork ? null : const WriteFilesResult();
  final shared = {for (final f in files) if (f.shared) f.path};
  return writeFilesToFolder(folder, {for (final f in plan.toWrite) f.path: f.content}, overwrite: true, neverOverwrite: shared);
}

/// The dialog of [saveChangedGeneratedFiles]: a summary, then a unified diff per file that would be written. Pops `true`
/// to write.
Future<bool?> showChangePreview(BuildContext context, String folder, FileChangePlan plan) => showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = context.colors;
        final styles = context.textStyles;
        final created = plan.created;
        final changed = plan.changed;
        final summary = [
          '${created.length} new',
          '${changed.length} changed',
          '${plan.unchanged.length} already up to date',
          if (plan.keptShared.isNotEmpty) '${plan.keptShared.length} shared kept as they are',
        ].join(' · ');
        final shown = [...changed, ...created];
        return AlertDialog(
          key: const ValueKey('change-preview'),
          title: Text(plan.hasWork ? 'Write changed files only' : 'Everything is up to date'),
          content: SizedBox(
            width: 760,
            height: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(folder, style: styles.caption.copyWith(color: colors.secondaryText)),
                const SizedBox(height: 4),
                Text(summary, style: styles.body.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Expanded(
                  child: shown.isEmpty
                      ? Text(
                          'Every generated file is already in this folder with the same content, so nothing is written.',
                          style: styles.body,
                        )
                      : ListView(
                          primary: false,
                          children: [
                            for (var i = 0; i < shown.length; i++)
                              ExpansionTile(
                                key: ValueKey('${shown[i].kind.name}:${shown[i].path}'),
                                initiallyExpanded: i == 0,
                                tilePadding: EdgeInsets.zero,
                                leading: Icon(
                                  shown[i].kind == FileChangeKind.created ? Icons.add_circle_outline : Icons.sync_alt,
                                  size: 18,
                                  color: shown[i].kind == FileChangeKind.created ? colors.statusSuccess : colors.statusWarning,
                                ),
                                title: Text(shown[i].path, style: styles.mono),
                                subtitle: Text(
                                  '${shown[i].kind == FileChangeKind.created ? 'new file' : 'changed'}: '
                                  '+${shown[i].diff?.added ?? 0} -${shown[i].diff?.removed ?? 0}',
                                  style: styles.caption.copyWith(color: colors.secondaryText),
                                ),
                                children: [_DiffText(text: shown[i].diffText)],
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(plan.hasWork ? 'Cancel' : 'Close')),
            if (plan.hasWork)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Write ${plan.toWrite.length} file${plan.toWrite.length == 1 ? '' : 's'}'),
              ),
          ],
        );
      },
    );

/// A unified diff with the added and removed lines tinted.
class _DiffText extends StatelessWidget {
  final String text;
  const _DiffText({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mono = context.textStyles.mono;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.appBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: SelectableText.rich(
        TextSpan(
          children: [
            for (final line in text.split('\n'))
              TextSpan(
                text: '$line\n',
                style: mono.copyWith(
                  color: line.startsWith('+') && !line.startsWith('+++')
                      ? colors.statusSuccess
                      : line.startsWith('-') && !line.startsWith('---')
                          ? colors.statusError
                          : line.startsWith('@@')
                              ? colors.secondaryText
                              : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
