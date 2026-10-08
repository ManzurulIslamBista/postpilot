import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../git_sync/domain/services/secret_names.dart';
import '../domain/entities/matrix_identity.dart';

/// What the identity editor decided.
final class IdentityEdit {
  /// The identity to keep; null when it was deleted.
  final MatrixIdentity? identity;
  const IdentityEdit.save(MatrixIdentity this.identity);
  const IdentityEdit.delete() : identity = null;
  bool get isDelete => identity == null;
}

/// Edits one identity: a name and the variables it sets. A variable with an empty value is *cleared*, which is how an
/// "anonymous" caller is made: the token is still defined, it is just empty.
class MatrixIdentityDialog extends StatefulWidget {
  final MatrixIdentity identity;

  /// A new identity cannot be deleted yet.
  final bool isNew;

  const MatrixIdentityDialog({super.key, required this.identity, this.isNew = false});

  static Future<IdentityEdit?> show(BuildContext context, {required MatrixIdentity identity, bool isNew = false}) =>
      ToolDialog.show<IdentityEdit>(context, (_) => MatrixIdentityDialog(identity: identity, isNew: isNew));

  @override
  State<MatrixIdentityDialog> createState() => _MatrixIdentityDialogState();
}

/// One variable row of the editor; [id] keeps its fields apart when rows are added and removed.
final class _Draft {
  static int _next = 0;
  final int id = _next++;
  String key;
  String value;
  _Draft(this.key, this.value);
}

class _MatrixIdentityDialogState extends State<MatrixIdentityDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.identity.name);
  late final List<_Draft> _rows = [
    for (final e in widget.identity.variables.entries) _Draft(e.key, e.value),
    if (widget.identity.variables.isEmpty) _Draft('', ''),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The rows that name a variable; the last of two rows with one name wins.
  Map<String, String> get _variables => {
        for (final r in _rows)
          if (r.key.trim().isNotEmpty) r.key.trim(): r.value,
      };

  String? get _error {
    if (_name.text.trim().isEmpty) return 'Give the identity a name.';
    if (_variables.isEmpty) return 'Add at least one variable.';
    return null;
  }

  void _save() {
    if (_error != null) return;
    Navigator.of(context).pop(IdentityEdit.save(widget.identity.copyWith(name: _name.text.trim(), variables: _variables)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final error = _error;
    return ToolDialog(
      icon: Icons.person_outline,
      title: widget.isNew ? 'New identity' : 'Edit identity',
      subtitle: 'Who is asking: variables put on top of the environment',
      width: 560,
      height: 600,
      footerLeading: error == null ? null : Text(error, style: context.textStyles.caption.copyWith(color: colors.statusWarning)),
      actions: [
        if (!widget.isNew)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: colors.statusError),
            onPressed: () => Navigator.of(context).pop(const IdentityEdit.delete()),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: error == null ? _save : null, child: const Text('Save')),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'admin, user, anonymous'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text('Variables', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Each one beats the environment\'s variable of the same name. Leave the value empty to clear the variable: '
              'the request is then sent without it, like a caller who is not signed in.',
              style: context.textStyles.caption.copyWith(color: colors.secondaryText),
            ),
            const SizedBox(height: 8),
            for (final row in _rows)
              _VariableRow(
                key: ValueKey(row.id),
                draft: row,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() => _rows.remove(row)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _rows.add(_Draft('', ''))),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add variable'),
              ),
            ),
            const SizedBox(height: 8),
            const InfoBanner(
              kind: BannerKind.info,
              message: 'Saved on this computer only, for this workplace. The values are never written to the workspace file, '
                  'to Git, to a backup or to an export of the results.',
            ),
          ],
        ),
      ),
    );
  }
}

/// A name and a value; the value is hidden while the name looks like a credential.
class _VariableRow extends StatefulWidget {
  final _Draft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _VariableRow({super.key, required this.draft, required this.onChanged, required this.onRemove});

  @override
  State<_VariableRow> createState() => _VariableRowState();
}

class _VariableRowState extends State<_VariableRow> {
  late final TextEditingController _key = TextEditingController(text: widget.draft.key);
  late final TextEditingController _value = TextEditingController(text: widget.draft.value);
  bool _reveal = false;

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  bool get _secret => SecretNames.looksSecretKey(_key.text.trim());

  @override
  Widget build(BuildContext context) {
    final hidden = _secret && !_reveal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: TextField(
              controller: _key,
              decoration: const InputDecoration(labelText: 'Variable', hintText: 'token'),
              onChanged: (v) {
                widget.draft.key = v;
                widget.onChanged();
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: TextField(
              controller: _value,
              obscureText: hidden,
              decoration: InputDecoration(
                labelText: 'Value',
                hintText: 'empty clears it',
                suffixIcon: _secret
                    ? IconButton(
                        icon: Icon(_reveal ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                        tooltip: _reveal ? 'Hide the value' : 'Show the value',
                        onPressed: () => setState(() => _reveal = !_reveal),
                      )
                    : null,
              ),
              onChanged: (v) {
                widget.draft.value = v;
                widget.onChanged();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove the variable',
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}
