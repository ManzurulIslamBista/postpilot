import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../view_models/odoo_studio_view_model.dart';
import 'odoo_flutter_client_tab.dart';
import 'odoo_studio_dialog.dart';

/// The "Odoo client" tab of Dart Studio: the same generator as Odoo Studio's "Flutter client" tab, connected through the
/// active environment (`odooUrl`, `odooDb`, `odooApiKey`). Another server is chosen in Odoo Studio's Connect tab.
class OdooClientStudioPane extends StatefulWidget {
  const OdooClientStudioPane({super.key});

  @override
  State<OdooClientStudioPane> createState() => _OdooClientStudioPaneState();
}

class _OdooClientStudioPaneState extends State<OdooClientStudioPane> {
  // A tab strip builds its neighbours too, so this must not fail where Odoo is not set up (a test harness).
  late final OdooStudioViewModel? _studio =
      locator.isRegistered<OdooStudioViewModel>() ? (locator<OdooStudioViewModel>()..loadFromActiveEnvironment()) : null;

  @override
  void dispose() {
    _studio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studio = _studio;
    if (studio == null) {
      return const EmptyHint(
        icon: Icons.hub_outlined,
        title: 'Odoo is not available here',
        message: 'Open Odoo Studio from the command palette to generate a Flutter client for Odoo.',
      );
    }
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: studio,
                  builder: (context, _) => Text(
                    studio.url.trim().isEmpty
                        ? 'No Odoo server in the active environment. Connect one in Odoo Studio (Connect tab), then come back.'
                        : 'Server: ${studio.url}${studio.database.isEmpty ? '' : ' · ${studio.database}'}  (from the active environment)',
                    style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => OdooStudioDialog.show(context, initialTab: OdooStudioTab.connect.index),
                icon: const Icon(Icons.hub_outlined, size: 16),
                label: const Text('Open Odoo Studio'),
              ),
            ],
          ),
        ),
        Expanded(child: OdooFlutterClientTab(viewModel: studio)),
      ],
    );
  }
}
