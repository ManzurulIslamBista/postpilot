import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/presentation/widgets/key_value_editor.dart';
import '../../../request_builder/presentation/widgets/response_viewer.dart';
import '../../domain/entities/cloud_request_entity.dart';
import '../../domain/entities/member_role.dart';
import '../view_models/team_view_model.dart';

/// Editor for a single [CloudRequestEntity]: name, method, URL, headers and
/// a single raw-text body — see the MVP scope note on [CloudRequestEntity]
/// for why there's no body-type switcher or auth/query-param editing here.
///
/// There is no Save button: every edit is applied to a local draft
/// synchronously and handed to [TeamViewModel.editRequest], which debounces
/// the cloud write. The draft stays the source of truth while the dialog is
/// open, so realtime echoes of our own saves can't clobber in-progress
/// typing (same reasoning as `_KeyValueRow`'s local copy).
///
/// Closing (X, Esc or the barrier) waits for the pending save; if it still
/// fails the user is asked before the edits are discarded. [canEdit] is only
/// the role at open time: the live role is re-checked so the editor turns
/// read-only when edit access is lost.
///
/// Send runs the request as it stands (unsaved edits included) and shows the
/// response under the form; anyone who can open the request can send it,
/// viewers included. It is sent without a local collection, so collection
/// variables and auth don't apply — see `CloudRequestMapper.toSendable`.
class RequestFormDialog extends StatefulWidget {
  final CloudRequestEntity request;
  final bool canEdit;

  const RequestFormDialog({super.key, required this.request, required this.canEdit});

  /// [context] must be able to reach the [TeamViewModel]; the dialog itself
  /// lives on the root navigator, so the provider is re-attached here.
  static Future<void> show(BuildContext context, {required CloudRequestEntity request, required bool canEdit}) {
    final vm = context.read<TeamViewModel>();
    return showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider<TeamViewModel>.value(
        value: vm,
        child: RequestFormDialog(request: request, canEdit: canEdit),
      ),
    );
  }

  @override
  State<RequestFormDialog> createState() => _RequestFormDialogState();
}

class _RequestFormDialogState extends State<RequestFormDialog> {
  late final TeamViewModel _vm = context.read<TeamViewModel>();
  late CloudRequestEntity _draft = widget.request;
  late final _nameController = TextEditingController(text: widget.request.name);
  late final _urlController = TextEditingController(text: widget.request.url);
  late final _bodyController = TextEditingController(text: widget.request.body);
  RequestSaveStatus _lastStatus = RequestSaveStatus.idle;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _vm.startRequestEdit(widget.request);
    _vm.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _vm.cancelSend();
    // Deferred: dispose runs while the widget tree is locked, and the flush
    // notifies listeners synchronously.
    scheduleMicrotask(() => unawaited(_vm.flushRequestSave()));
    _nameController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    final status = _vm.saveStatus;
    if (status == _lastStatus) return;
    _lastStatus = status;
    if (status == RequestSaveStatus.failed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_vm.errorMessage ?? 'Failed to save request')));
    }
  }

  void _apply(CloudRequestEntity Function(CloudRequestEntity) transform) {
    _draft = transform(_draft);
    _vm.editRequest(_draft);
  }

  void _send() => unawaited(_vm.sendRequest(_draft));

  Future<void> _requestClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await _vm.retryRequestSave();
      if (!mounted) return;
      if (_vm.hasUnsavedRequestEdits) {
        final discard = await showConfirmDialog(
          context,
          title: 'Unsaved changes',
          message: '${_vm.errorMessage ?? 'Failed to save request'}. Discard your changes?',
          confirmLabel: 'Discard',
        );
        if (!discard || !mounted) return;
        _vm.discardRequestEdits();
      }
      Navigator.pop(context);
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: _buildDialog(context),
    );
  }

  Widget _buildDialog(BuildContext context) {
    final userId = context.select<AuthViewModel, String?>((auth) => auth.currentUser?.id);
    final role = context.select<TeamViewModel, MemberRole?>((vm) => userId == null ? null : vm.myRole(userId));
    final canEdit = widget.canEdit && (role == MemberRole.owner || role == MemberRole.editor);
    final bold = context.textStyles.body.copyWith(fontWeight: FontWeight.bold);
    final showResponse = context.select<TeamViewModel, bool>((vm) => vm.hasSendResult);
    return Dialog(
      child: SizedBox(
        width: showResponse ? 640 : 480,
        height: showResponse ? 820 : 560,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(canEdit ? 'Edit request' : 'Request', style: context.textStyles.heading)),
                  if (canEdit) const _SaveIndicator(),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => unawaited(_requestClose())),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                readOnly: !canEdit,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (v) => _apply((r) => r.copyWith(name: v.trim().isEmpty ? r.name : v.trim())),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  DropdownButton<HttpMethod>(
                    value: HttpMethod.fromString(_draft.method),
                    items: [for (final m in HttpMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
                    onChanged: canEdit
                        ? (m) {
                            if (m != null) setState(() => _apply((r) => r.copyWith(method: m.label)));
                          }
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      readOnly: !canEdit,
                      decoration: const InputDecoration(labelText: 'URL'),
                      onChanged: (v) => _apply((r) => r.copyWith(url: v.trim())),
                    ),
                  ),
                  if (_vm.canSendRequests) ...[const SizedBox(width: 8), _SendButton(urlController: _urlController, onSend: _send)],
                ],
              ),
              const SizedBox(height: 12),
              Text('Headers', style: bold),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: canEdit
                      ? KeyValueEditor(
                          items: _draft.headers,
                          onChanged: (items) => setState(() => _apply((r) => r.copyWith(headers: items))),
                        )
                      : _ReadOnlyHeaders(headers: _draft.headers),
                ),
              ),
              const SizedBox(height: 8),
              Text('Body', style: bold),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _bodyController,
                  readOnly: !canEdit,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: context.textStyles.mono,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  onChanged: (v) => _apply((r) => r.copyWith(body: v)),
                ),
              ),
              if (showResponse) ...[
                const Divider(height: 24),
                Expanded(flex: 5, child: _ResponsePanel(requestName: _draft.name)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Send while idle, Cancel while a send is in flight. Listens to the URL field
/// itself: typing there doesn't rebuild the dialog.
class _SendButton extends StatelessWidget {
  final TextEditingController urlController;
  final VoidCallback onSend;
  const _SendButton({required this.urlController, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeamViewModel>();
    if (vm.isSendingRequest) {
      return OutlinedButton.icon(icon: const Icon(Icons.stop, size: 16), label: const Text('Cancel'), onPressed: vm.cancelSend);
    }
    return ListenableBuilder(
      listenable: urlController,
      builder: (context, _) => FilledButton.icon(
        icon: const Icon(Icons.send, size: 16),
        label: const Text('Send'),
        onPressed: urlController.text.trim().isEmpty ? null : onSend,
      ),
    );
  }
}

/// The outcome of the last send: progress while it runs, a friendly message
/// when it failed, and the shared response viewer (status, time, size, body,
/// headers) when it succeeded. The viewer is bound to request id 0: a cloud
/// request has no local row, so there are no saved examples to list and none
/// can be saved.
class _ResponsePanel extends StatelessWidget {
  final String requestName;
  const _ResponsePanel({required this.requestName});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeamViewModel>();
    final response = vm.sendResponse;
    final error = vm.sendError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (vm.isSendingRequest)
          Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Sending…', style: context.textStyles.caption),
            ],
          ),
        if (error != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: context.colors.statusError),
              const SizedBox(width: 6),
              Expanded(child: Text(error, style: context.textStyles.body.copyWith(color: context.colors.statusError))),
            ],
          ),
        if (response != null)
          Expanded(
            child: ResponseViewer(response: response, requestId: 0, requestName: requestName, canSaveExamples: false),
          ),
      ],
    );
  }
}

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeamViewModel>();
    final caption = context.textStyles.caption.copyWith(color: context.colors.secondaryText);
    return switch (vm.saveStatus) {
      RequestSaveStatus.idle => const SizedBox.shrink(),
      RequestSaveStatus.saving => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 6),
            Text('Saving…', style: caption),
          ],
        ),
      RequestSaveStatus.saved => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 14, color: context.colors.statusSuccess),
            const SizedBox(width: 4),
            Text('Saved', style: caption),
          ],
        ),
      RequestSaveStatus.failed => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: context.colors.statusError),
            const SizedBox(width: 4),
            Text('Save failed', style: caption.copyWith(color: context.colors.statusError)),
            TextButton(onPressed: () => unawaited(vm.retryRequestSave()), child: const Text('Retry')),
          ],
        ),
    };
  }
}

class _ReadOnlyHeaders extends StatelessWidget {
  final List<KeyValueItem> headers;
  const _ReadOnlyHeaders({required this.headers});

  @override
  Widget build(BuildContext context) {
    if (headers.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No headers', style: context.textStyles.caption));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final h in headers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText(
              '${h.key}: ${h.value}',
              style: context.textStyles.mono.copyWith(color: h.enabled ? null : context.colors.secondaryText),
            ),
          ),
      ],
    );
  }
}
