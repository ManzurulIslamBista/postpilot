import '../../../../core/widgets/busy_label.dart';
import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/presentation/widgets/auth_editor.dart';
import '../../domain/repositories/collection_auth_repository.dart';

/// Edits the auth every request set to "Inherit from parent" falls back to.
class CollectionAuthDialog extends StatefulWidget {
  final int collectionId;
  const CollectionAuthDialog({super.key, required this.collectionId});

  /// Not dismissible by a scrim click or Esc: everything typed here, and any
  /// token fetched through the browser, lives only in memory until Save.
  static Future<void> show(BuildContext context, {required int collectionId}) => showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => CollectionAuthDialog(collectionId: collectionId),
  );

  @override
  State<CollectionAuthDialog> createState() => _CollectionAuthDialogState();
}

class _CollectionAuthDialogState extends State<CollectionAuthDialog> {
  final _repository = locator<CollectionAuthRepository>();
  RequestAuth? _auth;
  String? _loadedJson;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stored = RequestAuth.fromJsonString(await _repository.getAuthJson(widget.collectionId)) ?? RequestAuth.none;
    final auth = stored.type == AuthType.inherit ? RequestAuth.none : stored;
    if (!mounted) return;
    setState(() {
      _auth = auth;
      _loadedJson = auth.toJsonString();
    });
  }

  bool get _hasUnsavedChanges => _auth != null && _auth!.toJsonString() != _loadedJson;

  Future<void> _close() async {
    if (_hasUnsavedChanges && !await _confirmDiscard()) return;
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits, and any token you fetched, have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _save() async {
    final auth = _auth;
    if (auth == null || _saving) return;
    setState(() => _saving = true);
    await _repository.setAuthJson(widget.collectionId, auth.toJsonString());
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('Collection auth saved')));
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    return Dialog(
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Collection auth', style: context.textStyles.heading),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: _close),
                ],
              ),
              Text(
                'Requests set to "Inherit from parent" use this auth.',
                style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
              ),
              const Divider(),
              Flexible(
                child: auth == null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : SingleChildScrollView(
                        child: AuthEditor(
                          auth: auth,
                          allowInherit: false,
                          collectionId: widget.collectionId,
                          showRelogin: true,
                          onChanged: (updated) => setState(() => _auth = updated),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _close, child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: auth == null || _saving ? null : _save,
                    child: BusyLabel(busy: _saving, label: 'Save', busyLabel: 'Saving…'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
