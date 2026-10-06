import 'package:flutter/material.dart';
import '../../../../core/network/upload_body.dart';
import '../../../../core/network/upload_file_source.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../file_picker_service.dart';
import 'variables/variable_text_form_field.dart';

/// The file of a form-data `file` row or of a binary body: a path that may hold `{{variables}}` (so a team can share
/// `{{uploadDir}}/avatar.png`), a "Choose file…" button, the name and size of what is there, and Remove.
///
/// Only the reference is edited here, and only the reference is saved: the bytes are read from the disk when the
/// request is sent. A browser gives no path and cannot reopen a file later, so there the chosen bytes are kept in
/// memory for the session ([SessionFiles]) and the field says so, and after a reload asks for the file again.
///
/// It keeps its own copy of the three values and reports changes as the values that changed, so a row that owns the
/// rest of the item (its key, its switch) is never overwritten by a stale copy (see `KeyValueEditor`).
class FileField extends StatefulWidget {
  final String path;
  final String fileName;
  final String contentType;

  /// Called with only what changed.
  final void Function({String? path, String? fileName, String? contentType}) onChanged;
  final FilePickerService picker;

  /// Where the size and state of the file are looked up from; the disk, or in a browser the session's files.
  final UploadFileSource? source;

  /// A form part has a name of its own (`filename=`); the body of a binary request has none.
  final bool showFileName;

  const FileField({
    super.key,
    required this.path,
    required this.fileName,
    required this.contentType,
    required this.onChanged,
    required this.picker,
    this.source,
    this.showFileName = true,
  });

  @override
  State<FileField> createState() => _FileFieldState();
}

class _FileFieldState extends State<FileField> {
  late String _path = widget.path;
  late String _fileName = widget.fileName;
  late String _contentType = widget.contentType;
  late final UploadFileSource _source = widget.source ?? createUploadFileSource();

  UploadFileCheck? _check;
  int _checkToken = 0;
  bool _picking = false;
  String? _pickError;
  late bool _showOptions = _fileName.isNotEmpty || _contentType.isNotEmpty;

  /// Bumped when the path changes from outside the text field, so it shows the new text.
  int _pathRevision = 0;
  int _optionsRevision = 0;

  @override
  void initState() {
    super.initState();
    _look();
  }

  /// Another request was opened, or the item was changed from outside (the field's own edits are already in its
  /// copy, so they do not count): show what the parent holds now.
  @override
  void didUpdateWidget(covariant FileField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path == _path && widget.fileName == _fileName && widget.contentType == _contentType) return;
    _path = widget.path;
    _fileName = widget.fileName;
    _contentType = widget.contentType;
    _showOptions = _fileName.isNotEmpty || _contentType.isNotEmpty;
    _pathRevision++;
    _optionsRevision++;
    _pickError = null;
    _look();
  }

  Future<void> _look() async {
    final token = ++_checkToken;
    final check = await _source.check(_path);
    if (!mounted || token != _checkToken) return;
    setState(() => _check = check);
  }

  void _emit({String? path, String? fileName, String? contentType}) {
    widget.onChanged(path: path, fileName: fileName, contentType: contentType);
  }

  void _typePath(String text) {
    _path = text;
    _emit(path: text);
    _look();
  }

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _pickError = null;
    });
    try {
      final picked = await widget.picker.pick();
      if (!mounted) return;
      if (picked != null) {
        _path = picked.path;
        _pathRevision++;
        _emit(path: picked.path);
      }
    } on FilePickRefused catch (e) {
      if (mounted) _pickError = e.message;
    } catch (_) {
      if (mounted) _pickError = 'The file could not be opened. Choose it again, or type its path.';
    }
    if (!mounted) return;
    setState(() => _picking = false);
    _look();
  }

  void _remove() {
    SessionFiles.shared.remove(_path);
    setState(() {
      _path = '';
      _fileName = '';
      _contentType = '';
      _showOptions = false;
      _pathRevision++;
      _optionsRevision++;
      _pickError = null;
    });
    _emit(path: '', fileName: '', contentType: '');
    _look();
  }

  @override
  Widget build(BuildContext context) {
    final sessionFile = SessionFiles.isReference(_path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: sessionFile
                  ? _ChosenName(name: FilePaths.baseName(_path))
                  : VariableTextFormField(
                      key: ValueKey('file-path-$_pathRevision'),
                      initialValue: _path,
                      decoration: const InputDecoration(hintText: 'File path, e.g. {{uploadDir}}/avatar.png', isDense: true),
                      onChanged: _typePath,
                    ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('file-choose'),
              onPressed: _picking ? null : _pick,
              child: BusyLabel(
                busy: _picking,
                label: _path.isEmpty ? 'Choose file…' : 'Change…',
                busyLabel: 'Reading file…',
                icon: Icons.attach_file,
                iconSize: 16,
              ),
            ),
          ],
        ),
        _status(context),
        if (_showOptions) _options(context),
      ],
    );
  }

  Widget _status(BuildContext context) {
    final colors = context.colors;
    final style = context.textStyles.caption;
    final check = _check;
    final pieces = <Widget>[];

    if (_pickError != null) {
      pieces.add(Text(_pickError!, style: style.copyWith(color: colors.statusError)));
    } else if (_path.trim().isEmpty) {
      pieces.add(Text('No file chosen', style: style.copyWith(color: colors.secondaryText)));
    } else if (check?.problem != null) {
      pieces.add(Text(check!.problem!, key: const ValueKey('file-problem'), style: style.copyWith(color: colors.statusWarning)));
    } else if (check?.unresolved == true) {
      pieces.add(Text('Found when the request is sent: the path uses a variable', style: style.copyWith(color: colors.secondaryText)));
    } else if (check?.size != null) {
      final name = _fileName.isNotEmpty ? _fileName : FilePaths.baseName(_path);
      pieces.add(Text('$name · ${UploadLimits.describe(check!.size!)}', key: const ValueKey('file-summary'), style: style));
      if (SessionFiles.isReference(_path)) {
        pieces.add(Text(
          'selected in this session only: after a reload, choose the file again',
          key: const ValueKey('file-session-note'),
          style: style.copyWith(color: colors.statusWarning),
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...pieces,
          if (_path.trim().isNotEmpty)
            TextButton.icon(
              key: const ValueKey('file-remove'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: _remove,
              icon: const Icon(Icons.close, size: 14),
              label: const Text('Remove'),
            ),
          TextButton(
            key: const ValueKey('file-options'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => setState(() => _showOptions = !_showOptions),
            child: Text(_showOptions ? 'Hide options' : 'Options'),
          ),
        ],
      ),
    );
  }

  Widget _options(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (widget.showFileName)
            SizedBox(
              width: 220,
              child: VariableTextFormField(
                key: ValueKey('file-name-$_optionsRevision'),
                initialValue: _fileName,
                decoration: const InputDecoration(labelText: 'File name sent', hintText: "The file's own name", isDense: true),
                onChanged: (v) {
                  _fileName = v;
                  _emit(fileName: v);
                  setState(() {});
                },
              ),
            ),
          SizedBox(
            width: 220,
            child: VariableTextFormField(
              key: ValueKey('file-content-type-$_optionsRevision'),
              initialValue: _contentType,
              decoration: InputDecoration(
                labelText: 'Content-Type',
                hintText: widget.showFileName ? 'Guessed from the file name' : BinaryUpload.defaultContentType,
                isDense: true,
              ),
              onChanged: (v) {
                _contentType = v;
                _emit(contentType: v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The name of a file chosen in a browser session, where there is no path to type.
class _ChosenName extends StatelessWidget {
  final String name;
  const _ChosenName({required this.name});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.insert_drive_file_outlined, size: 16)),
      child: Text(name, overflow: TextOverflow.ellipsis, style: context.textStyles.body),
    );
  }
}
