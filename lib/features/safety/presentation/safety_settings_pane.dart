import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../settings/presentation/widgets/setting_row.dart';
import '../data/safety_prefs.dart';
import '../domain/services/production_detector.dart';

/// Settings > Safety: the production lock and what counts as production.
class SafetySettingsPane extends StatefulWidget {
  const SafetySettingsPane({super.key});

  @override
  State<SafetySettingsPane> createState() => _SafetySettingsPaneState();
}

class _SafetySettingsPaneState extends State<SafetySettingsPane> {
  // A screen built without the app container (a test, a preview) gets throwaway preferences.
  final SafetyPrefs _prefs = locator.isRegistered<SafetyPrefs>() ? locator<SafetyPrefs>() : SafetyPrefs();
  late final TextEditingController _words = TextEditingController(text: _prefs.extraWords.join(', '));
  late final TextEditingController _hosts = TextEditingController(text: _prefs.productionHosts.join(', '));

  @override
  void dispose() {
    _words.dispose();
    _hosts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Safety', style: context.textStyles.heading),
          SettingRow(
            title: 'Production lock',
            description: 'Ask before sending a request that changes data (POST, PUT, PATCH, DELETE, an Odoo write, a GraphQL mutation) '
                'and before running a collection that does, while the active environment looks like production. '
                'Reads over POST, such as an Odoo search_read or a GraphQL query, are not asked about. '
                'Deleting data (DELETE, unlink, a delete mutation) is always asked about, even after "Don\'t ask again". '
                'The environment picker turns red as a reminder.',
            control: Switch(value: _prefs.confirmProductionWrites, onChanged: _prefs.setConfirmProductionWrites),
          ),
          SettingRow(
            title: 'Keep secrets on this device',
            description: 'Passwords, tokens and secret variables are saved in workspace.local.json beside your workspace, '
                'not in workspace.json. Git only carries workspace.json, so teammates never receive your secrets '
                'and they can fill in their own. Takes effect at the next save.',
            control: Switch(value: _prefs.keepSecretsLocal, onChanged: _prefs.setKeepSecretsLocal),
          ),
          SettingRow(
            title: 'Names that mean production',
            description: 'Environments with the words ${ProductionDetector.builtInWords.join(', ')} are protected. '
                'Add your own words, separated by commas (for example: eu-west, customer-a).',
            control: SizedBox(
              width: 220,
              child: TextField(
                controller: _words,
                decoration: const InputDecoration(hintText: 'eu-west, customer-a'),
                onChanged: (v) => _prefs.setExtraWords(v.split(',')),
              ),
            ),
          ),
          SettingRow(
            title: 'Production hosts',
            description: 'A request sent to one of these hosts is protected whatever the environment is called, '
                'so a Dev environment that points at the live server cannot slip through. '
                'Separate with commas. A host also covers its subdomains, and a port limits it '
                '(for example: api.acme.com, *.acme.com, acme.com:8443).',
            control: SizedBox(
              width: 220,
              child: TextField(
                controller: _hosts,
                decoration: const InputDecoration(hintText: 'api.acme.com, *.acme.com'),
                onChanged: (v) => _prefs.setProductionHosts(v.split(',')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
