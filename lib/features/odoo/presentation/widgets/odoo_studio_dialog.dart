import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../view_models/odoo_studio_view_model.dart';
import 'odoo_check_tab.dart';
import 'odoo_connect_tab.dart';
import 'odoo_convert_tab.dart';
import 'odoo_dart_tab.dart';
import 'odoo_domain_tab.dart';
import 'odoo_explorer_tab.dart';
import 'odoo_payload_tab.dart';

/// The tabs of Odoo Studio, in order; [OdooStudioDialog.show] opens one by its [index].
enum OdooStudioTab { connect, explorer, domain, payload, check, migrate, dart }

/// Odoo, end to end, for developers: connect (Odoo 19+ JSON-2 with an API key, or Odoo 18 and older with a JSON-RPC
/// login) and save the server as an environment, generate the requests, explore models and fields, build domains and
/// create/write payloads visually, check a body against the live schema, migrate old XML-RPC / JSON-RPC calls, and
/// generate Dart classes for Flutter.
class OdooStudioDialog extends StatefulWidget {
  final int initialTab;
  const OdooStudioDialog({super.key, this.initialTab = 0});

  static Future<void> show(BuildContext context, {int initialTab = 0}) =>
      ToolDialog.show(context, (_) => OdooStudioDialog(initialTab: initialTab));

  @override
  State<OdooStudioDialog> createState() => _OdooStudioDialogState();
}

class _OdooStudioDialogState extends State<OdooStudioDialog> {
  late final OdooStudioViewModel _vm = locator<OdooStudioViewModel>()..loadFromActiveEnvironment();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ToolDialog(
      icon: Icons.hub_outlined,
      title: 'Odoo Studio',
      subtitle: 'JSON-2 and JSON-RPC · explore models · domains · payloads · request check · migrate old RPC · Dart classes',
      width: 1040,
      height: 700,
      child: ToolTabs(
        initialIndex: widget.initialTab.clamp(0, OdooStudioTab.values.length - 1),
        tabs: [
          ToolTab(label: 'Connect', icon: Icons.power_outlined, child: OdooConnectTab(viewModel: _vm)),
          ToolTab(label: 'Explorer', icon: Icons.travel_explore, child: OdooExplorerTab(viewModel: _vm)),
          ToolTab(label: 'Domain builder', icon: Icons.filter_alt_outlined, child: OdooDomainTab(viewModel: _vm)),
          ToolTab(label: 'Payload', icon: Icons.dynamic_form_outlined, child: OdooPayloadTab(viewModel: _vm)),
          ToolTab(label: 'Check', icon: Icons.fact_check_outlined, child: OdooCheckTab(viewModel: _vm)),
          ToolTab(label: 'Migrate RPC', icon: Icons.swap_horiz, child: OdooConvertTab(viewModel: _vm)),
          ToolTab(label: 'Dart model', icon: Icons.flutter_dash, child: OdooDartTab(viewModel: _vm)),
        ],
      ),
    );
  }
}
