import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../view_models/odoo_studio_view_model.dart';
import 'odoo_connect_tab.dart';
import 'odoo_convert_tab.dart';
import 'odoo_dart_tab.dart';
import 'odoo_domain_tab.dart';
import 'odoo_explorer_tab.dart';

/// Odoo, end to end, for developers who build on its External JSON-2 API:
/// connect and save the server as an environment, generate the requests,
/// explore models and fields, build domains visually, migrate old XML-RPC /
/// JSON-RPC calls, and generate Dart classes for Flutter.
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
      subtitle: 'JSON-2 API · explore models · domains · migrate old RPC · Dart classes',
      width: 1040,
      height: 700,
      child: ToolTabs(
        initialIndex: widget.initialTab,
        tabs: [
          ToolTab(label: 'Connect', icon: Icons.power_outlined, child: OdooConnectTab(viewModel: _vm)),
          ToolTab(label: 'Explorer', icon: Icons.travel_explore, child: OdooExplorerTab(viewModel: _vm)),
          ToolTab(label: 'Domain builder', icon: Icons.filter_alt_outlined, child: OdooDomainTab(viewModel: _vm)),
          ToolTab(label: 'Migrate RPC', icon: Icons.swap_horiz, child: OdooConvertTab(viewModel: _vm)),
          ToolTab(label: 'Dart model', icon: Icons.flutter_dash, child: OdooDartTab(viewModel: _vm)),
        ],
      ),
    );
  }
}
