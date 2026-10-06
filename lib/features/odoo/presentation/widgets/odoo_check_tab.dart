import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/entities/odoo_connection.dart';
import '../view_models/odoo_check_view_model.dart';
import '../view_models/odoo_studio_view_model.dart';
import 'odoo_problems_view.dart';

/// Checks a request body against the live schema of its model before it is sent: the model and the field names (with
/// "did you mean"), the types of the values, the required fields of `create`, the read-only ones, the shape of x2many
/// commands, the domain and its operators. Each problem comes with a one-click fix where one is obvious.
class OdooCheckTab extends StatelessWidget {
  final OdooStudioViewModel viewModel;
  const OdooCheckTab({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) => _StudioCheck(viewModel: viewModel);
}

class _StudioCheck extends StatefulWidget {
  final OdooStudioViewModel viewModel;
  const _StudioCheck({required this.viewModel});

  @override
  State<_StudioCheck> createState() => _StudioCheckState();
}

class _StudioCheckState extends State<_StudioCheck> {
  late final OdooCheckViewModel _vm = OdooCheckViewModel(widget.viewModel);

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OdooCheckPanel(viewModel: _vm, editableTarget: true);
}

/// The body and the problems side by side (stacked on a narrow screen). In Studio the model and the method are typed;
/// from a request tab they come from its URL and only the body is shown. [onBodyChanged] is told about the body after
/// a fix.
class OdooCheckPanel extends StatefulWidget {
  final OdooCheckViewModel viewModel;
  final bool editableTarget;
  final ValueChanged<String>? onBodyChanged;
  const OdooCheckPanel({super.key, required this.viewModel, this.editableTarget = false, this.onBodyChanged});

  @override
  State<OdooCheckPanel> createState() => _OdooCheckPanelState();
}

class _OdooCheckPanelState extends State<OdooCheckPanel> {
  static const _example = '{\n  "vals_list": [\n    {\n      "name": "Azure Interior",\n      "parnter_id": "Deco Addict",\n      "is_company": "yes"\n    }\n  ]\n}';

  late final _body = TextEditingController(text: widget.viewModel.bodyText);
  late final _model = TextEditingController(text: widget.viewModel.model);
  late final _method = TextEditingController(text: widget.viewModel.method);
  String _lastBody = '';

  OdooCheckViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _lastBody = _vm.bodyText;
    _vm.addListener(_follow);
  }

  /// A fix changed the body or the model: the boxes follow.
  void _follow() {
    if (_vm.bodyText != _body.text) _body.text = _vm.bodyText;
    if (_vm.model != _model.text) _model.text = _vm.model;
    if (_vm.bodyText != _lastBody) {
      _lastBody = _vm.bodyText;
      widget.onBodyChanged?.call(_vm.bodyText);
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_follow);
    _body.dispose();
    _model.dispose();
    _method.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final colors = context.colors;
        final problems = _vm.problems;
        final target = widget.editableTarget
            ? Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _model,
                      style: context.textStyles.mono,
                      decoration: const InputDecoration(labelText: 'Model', hintText: 'res.partner', isDense: true),
                      onChanged: (v) => _vm.setTarget(model: v.trim()),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _method,
                      style: context.textStyles.mono,
                      decoration: const InputDecoration(labelText: 'Method', hintText: 'create', isDense: true),
                      onChanged: (v) => _vm.setTarget(method: v.trim()),
                    ),
                  ),
                  SegmentedButton<OdooProtocol>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: OdooProtocol.json2, label: Text('JSON-2')),
                      ButtonSegment(value: OdooProtocol.jsonRpc, label: Text('call_kw')),
                    ],
                    selected: {_vm.protocol},
                    onSelectionChanged: (s) => _vm.setTarget(protocol: s.first),
                  ),
                ],
              )
            : Text(
                '${_vm.model.isEmpty ? '(model in a variable)' : _vm.model} · ${_vm.method.isEmpty ? '(method in a variable)' : _vm.method} · '
                '${_vm.protocol == OdooProtocol.json2 ? 'JSON-2' : 'call_kw'}',
                style: context.textStyles.mono.copyWith(color: colors.mainAccent, fontWeight: FontWeight.w600),
              );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: _vm.isBusy ? null : _vm.run,
              child: BusyLabel(busy: _vm.isBusy, icon: Icons.fact_check_outlined, label: 'Check', busyLabel: 'Checking…'),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Read the fields of this model from the server again, then check',
              onPressed: _vm.isBusy ? null : _vm.refresh,
            ),
            if (widget.editableTarget)
              TextButton(
                onPressed: () {
                  _vm.setBody(_example);
                  _body.text = _example;
                },
                child: const Text('Insert a bad example'),
              ),
          ],
        );
        final editor = TextField(
          controller: _body,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: context.textStyles.mono,
          decoration: const InputDecoration(
            hintText: 'The JSON body of the request:\n{"vals_list": [{"name": "Azure Interior"}]}\n\nor a call_kw body with params.model and params.method.',
            alignLabelWithHint: true,
          ),
          onChanged: _vm.setBody,
        );
        final results = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_vm.error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: InfoBanner(kind: BannerKind.warning, message: _vm.error!)),
            Expanded(
              child: problems == null
                  ? const EmptyHint(
                      icon: Icons.fact_check_outlined,
                      title: 'Check a request',
                      message: 'Press Check. The body is compared with the fields the server describes for the model, and each problem comes with a fix when there is an obvious one.',
                    )
                  : SingleChildScrollView(child: OdooProblemsView(problems: problems, onFix: _vm.applyFix, onFixAll: _vm.applyAll)),
            ),
          ],
        );
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              target,
              const SizedBox(height: 8),
              actions,
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => c.maxWidth >= 700
                      ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: editor), const SizedBox(width: 14), Expanded(child: results)])
                      : Column(children: [Expanded(flex: 2, child: editor), const SizedBox(height: 10), Expanded(flex: 3, child: results)]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
