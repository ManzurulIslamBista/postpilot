import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../collections/presentation/view_models/collections_view_model.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../safety/domain/services/production_guard.dart';
import '../../../safety/presentation/production_confirm_dialog.dart';
import '../../../shell/presentation/shell_view_model.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../view_models/history_view_model.dart';
import 'collection_chooser_dialog.dart';

/// What the buttons of the History panel do, with the dialogs they need. The
/// panel's own state lives in [HistoryViewModel]; this is the part that asks the
/// person something or opens a tab.
abstract final class HistoryActions {
  /// "Open as new request" and "Edit & re-send": saves the entry's request as a
  /// new request and opens it in a tab. It goes in the collection the entry was
  /// sent from; when that one is gone the person chooses, nothing is picked for them.
  /// With [copy] the request is named as a copy made from History.
  static Future<void> open(BuildContext context, HistoryViewModel vm, HistoryEntryEntity entry, {required bool copy}) async {
    final collections = context.read<CollectionsViewModel>();
    final shell = context.read<ShellViewModel>();
    final navigator = Navigator.of(context);
    final snapshot = await vm.snapshotOf(entry);
    var collectionId = await vm.originCollectionOf(snapshot);
    if (!context.mounted) return;

    if (collectionId == null) {
      final known = snapshot.meta.collectionId != null;
      // Reading the repository, not the view model's list, which is empty until its first emission lands.
      final first = await collections.ensureCollection();
      if (!context.mounted) return;
      if (first.created) {
        // A fresh install has no collection to choose from: the one made for it is the only possible place.
        collectionId = first.id;
      } else {
        final chosen = await showCollectionChooser(
          context,
          collections: collections.collections,
          reason: known
              ? 'The collection this request was sent from is not there any more.'
              : 'History did not keep which collection this request was sent from.',
          createCollection: collections.createCollection,
        );
        if (chosen == null || !context.mounted) return;
        collectionId = chosen;
      }
    }

    try {
      final requestId = await vm.openAsNewRequest(entry, collectionId: collectionId, copy: copy);
      collections.expandCollection(collectionId);
      shell.selectRequest(requestId);
      navigator.pop();
    } catch (error) {
      vm.tell(HistoryNoticeKind.error, 'The request could not be opened (${error.runtimeType}).');
    }
  }

  /// "Re-send as is": asks first when values were masked in History or the target looks like production.
  static Future<void> resend(BuildContext context, HistoryViewModel vm, HistoryEntryEntity entry) async {
    final snapshot = await vm.snapshotOf(entry);
    if (!context.mounted) return;
    await vm.resendAsIs(
      entry,
      confirm: (request) async {
        if (snapshot.hasMaskedValues) {
          final go = await showConfirmDialog(
            context,
            title: 'Send with masked values left empty?',
            message: 'Some values in this request (passwords or tokens) were masked when it was recorded, so they '
                'are sent empty. Use "Edit & re-send" to enter them first.',
            confirmLabel: 'Send anyway',
          );
          if (!go || !context.mounted) return false;
        }
        return confirmProduction(context, request);
      },
    );
  }

  /// The production lock: true when the send may go ahead. A data-changing request is asked about while
  /// a production environment is active, or when it goes to one of the production hosts of Settings > Safety.
  static Future<bool> confirmProduction(BuildContext context, ApiRequestEntity request) async {
    if (!locator.isRegistered<ProductionGuard>()) return true;
    final guard = locator<ProductionGuard>();
    final warning = await guard.checkRequest(request);
    if (warning == null || !context.mounted) return true;
    return confirmProductionSend(context, warning, onSilence: () => guard.silenceForSession(warning.environmentName));
  }

  /// Puts the cURL command of [entry] on the clipboard. The template form never resolves anything;
  /// [resolved] fills in the active environment's values on purpose and says so.
  static Future<void> copyCurl(
    BuildContext context,
    HistoryViewModel vm,
    HistoryEntryEntity entry, {
    required bool resolved,
  }) async {
    try {
      final text = resolved ? await vm.curlResolved(entry) : await vm.curlTemplate(entry);
      await Clipboard.setData(ClipboardData(text: text));
      vm.tell(
        resolved ? HistoryNoticeKind.warning : HistoryNoticeKind.success,
        resolved
            ? 'Copied the cURL command with the active environment\'s values filled in. It holds real secrets: do not share it.'
            : 'Copied the cURL command. {{variables}} are left as written and masked values stay masked.',
      );
    } catch (error) {
      vm.tell(HistoryNoticeKind.error, 'The cURL command could not be built (${error.runtimeType}).');
    }
  }
}
