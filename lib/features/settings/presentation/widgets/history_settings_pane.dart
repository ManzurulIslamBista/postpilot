import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../history/domain/repositories/history_repository.dart';
import '../../../history/domain/services/history_policy.dart';
import '../../data/history_prefs.dart';
import 'setting_number_field.dart';
import 'setting_row.dart';

/// Settings > History: what is kept with each request that was sent, and for how long.
class HistorySettingsPane extends StatefulWidget {
  const HistorySettingsPane({super.key});

  @override
  State<HistorySettingsPane> createState() => _HistorySettingsPaneState();
}

class _HistorySettingsPaneState extends State<HistorySettingsPane> {
  // A screen built without the app container (a test, a preview) gets throwaway preferences.
  final HistoryPrefs _prefs = locator.isRegistered<HistoryPrefs>() ? locator<HistoryPrefs>() : HistoryPrefs();
  bool _clearing = false;
  String? _clearResult;

  @override
  void initState() {
    super.initState();
    _prefs.load();
  }

  Future<void> _clear() async {
    if (!locator.isRegistered<HistoryRepository>()) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear history',
      message: 'Delete every recorded request, with the request and response details kept for them? '
          'This cannot be undone. Your collections and saved requests are not touched.',
      confirmLabel: 'Clear history',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _clearing = true;
      _clearResult = null;
    });
    String result;
    try {
      await locator<HistoryRepository>().clear();
      result = 'History is empty now.';
    } catch (error) {
      result = 'History could not be cleared (${error.runtimeType}).';
    }
    if (mounted) {
      setState(() {
        _clearing = false;
        _clearResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('History', style: context.textStyles.heading),
          SettingRow(
            title: 'Keep request/response bodies in history',
            description: 'Stores the request as it was saved ({{variables}} stay as written, passwords and tokens are masked) '
                'and a masked copy of the response text with each entry, so you can search it, see what came back and '
                'send it again. Off: only the method, URL, status and time are kept, and nothing new is stored beside them.',
            control: Switch(value: _prefs.keepBodies, onChanged: _prefs.setKeepBodies),
          ),
          SettingRow(
            title: 'Entries to keep',
            description: 'The newest ones are kept; older ones are removed as new requests are sent. '
                'Between ${HistoryLimits.minMaxEntries} and ${HistoryLimits.maxMaxEntries}.',
            control: SettingNumberField(value: _prefs.maxEntries, onChanged: _prefs.setMaxEntries, suffixText: 'entries'),
          ),
          SettingRow(
            title: 'Remove entries older than',
            description: 'Days an entry is kept. 0 keeps entries until the limit above pushes them out.',
            control: SettingNumberField(value: _prefs.retentionDays, onChanged: _prefs.setRetentionDays, suffixText: 'days'),
          ),
          SettingRow(
            title: 'Largest body kept per entry',
            description: 'A longer response (or request body) is cut after this many kilobytes and marked as cut.',
            control: SettingNumberField(value: _prefs.maxBodyKb, onChanged: _prefs.setMaxBodyKb, suffixText: 'KB'),
          ),
          SettingRow(
            title: 'Clear history',
            description: 'Deletes every recorded request and the details kept for them.',
            note: _clearResult,
            control: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: colors.statusError),
              onPressed: _clearing ? null : _clear,
              child: BusyLabel(busy: _clearing, label: 'Clear history', busyLabel: 'Clearing...', icon: Icons.delete_outline, iconSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
