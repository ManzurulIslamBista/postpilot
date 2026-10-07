import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/method_badge.dart';
import '../domain/services/mock_example_handler.dart';
import '../domain/services/mock_handler.dart';
import '../domain/services/mock_routes.dart';
import '../domain/services/mock_scenarios.dart';
import 'mock_network_menu.dart';
import 'mock_server_view_model.dart';

/// Make things go wrong on purpose, per route or for the whole server, while the server runs: an empty list, a 401, a slow answer,
/// a flaky one, a broken body, no answer at all. Below that, rules that pick one of a route's saved examples by what the request holds.
class MockScenariosTab extends StatelessWidget {
  final MockServerViewModel vm;
  const MockScenariosTab({super.key, required this.vm});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final routes = vm.routes;
    final any = !vm.scenarios.isAllNormal;
    return ListView(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      children: [
        Text(
          'A change here applies to the next request: nothing restarts. A route\'s own scenario replaces the one for the whole server, '
          'so "Normal" on a route keeps it working while everything else fails. The network (slow, lossy, offline...) is set for the '
          'whole server with the button at the top of this window, and per route with the button on its card.',
          style: context.textStyles.caption.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: 10),
        ToolSection(
          title: 'Whole server',
          child: _ScenarioEditor(
            key: const ValueKey('scenario-global'),
            scenario: vm.scenarios.global,
            inherit: false,
            onChanged: (s) => vm.setGlobalScenario(s ?? MockScenario.normal),
          ),
        ),
        ToolSection(
          title: 'Per route (${routes.length})',
          hint: routes.isEmpty ? 'The routes appear here once the server has them: start it, or load an OpenAPI document.' : null,
          child: Column(
            children: [
              for (final r in routes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RouteScenarioRow(key: ValueKey('scenario-${r.key}'), route: r, vm: vm),
                ),
              if (any || !vm.network.isIdle)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    // The scenarios and the network profiles both: nothing is left going wrong.
                    onPressed: () {
                      vm.clearScenarios();
                      vm.clearNetwork();
                    },
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Back to normal everywhere'),
                  ),
                ),
            ],
          ),
        ),
        _MatchRules(vm: vm),
      ],
    );
  }
}

class _RouteScenarioRow extends StatelessWidget {
  final MockRouteInfo route;
  final MockServerViewModel vm;
  const _RouteScenarioRow({super.key, required this.route, required this.vm});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MethodBadge(method: route.method, width: 44),
              const SizedBox(width: 8),
              Expanded(child: Text(route.path, style: context.textStyles.mono, overflow: TextOverflow.ellipsis)),
              // This route's own network (slow, lossy, offline...), in the title row so the card keeps its height.
              MockNetworkMenu(profile: vm.network.routes[route.key], inherit: true, onChanged: (p) => vm.setRouteNetwork(route.key, p)),
            ],
          ),
          const SizedBox(height: 8),
          _ScenarioEditor(
            scenario: vm.scenarios.routes[route.key],
            inherit: true,
            onChanged: (s) => vm.setRouteScenario(route.key, s),
          ),
        ],
      ),
    );
  }
}

/// The scenario picker with the settings its kind needs. [inherit] adds "Same as the whole server" (null).
class _ScenarioEditor extends StatefulWidget {
  final MockScenario? scenario;
  final bool inherit;
  final ValueChanged<MockScenario?> onChanged;

  const _ScenarioEditor({super.key, required this.scenario, required this.inherit, required this.onChanged});

  @override
  State<_ScenarioEditor> createState() => _ScenarioEditorState();
}

class _ScenarioEditorState extends State<_ScenarioEditor> {
  late MockScenario? _scenario = widget.scenario;
  late final _min = TextEditingController(text: '${(widget.scenario ?? const MockScenario(MockScenarioKind.slow)).latencyMinMs}');
  late final _max = TextEditingController(text: '${(widget.scenario ?? const MockScenario(MockScenarioKind.slow)).latencyMaxMs}');
  late final _every = TextEditingController(text: '${(widget.scenario ?? const MockScenario(MockScenarioKind.flaky)).failEvery}');
  late final _percent = TextEditingController(text: '${(widget.scenario ?? const MockScenario(MockScenarioKind.flaky)).failPercent}');
  late final _status = TextEditingController(text: '${(widget.scenario ?? const MockScenario(MockScenarioKind.flaky)).failStatus}');

  @override
  void didUpdateWidget(covariant _ScenarioEditor old) {
    super.didUpdateWidget(old);
    // Something else changed it (the "back to normal" button): follow.
    if (widget.scenario != old.scenario && widget.scenario != _scenario) _scenario = widget.scenario;
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    _every.dispose();
    _percent.dispose();
    _status.dispose();
    super.dispose();
  }

  int _int(TextEditingController c, int fallback) => int.tryParse(c.text.trim()) ?? fallback;

  void _pick(MockScenarioKind? kind) {
    setState(() {
      _scenario = kind == null ? null : MockScenario(kind, latencyMinMs: _int(_min, 1000), latencyMaxMs: _int(_max, 1000), failEvery: _int(_every, 0), failPercent: _int(_percent, 30), failStatus: _int(_status, 500));
    });
    widget.onChanged(_scenario);
  }

  /// A setting changed: the same kind with the new numbers.
  void _tune() {
    final current = _scenario;
    if (current == null) return;
    final next = current.copyWith(
      latencyMinMs: _int(_min, 1000),
      latencyMaxMs: _int(_max, 1000),
      failEvery: _int(_every, 0),
      failPercent: _int(_percent, 30).clamp(0, 100),
      failStatus: _int(_status, 500).clamp(100, 599),
    );
    setState(() => _scenario = next);
    widget.onChanged(next);
  }

  Widget _number(String label, TextEditingController controller, {String? suffix, double width = 100}) => SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, suffixText: suffix),
          onChanged: (_) => _tune(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final kind = _scenario?.kind;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 230,
          child: DropdownButtonFormField<MockScenarioKind?>(
            key: ValueKey('kind-$kind'),
            initialValue: kind,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Scenario'),
            items: [
              if (widget.inherit) const DropdownMenuItem<MockScenarioKind?>(value: null, child: Text('Same as the whole server')),
              for (final k in MockScenarioKind.values) DropdownMenuItem<MockScenarioKind?>(value: k, child: Text(k.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _pick,
          ),
        ),
        if (kind == MockScenarioKind.slow) ...[
          _number('From', _min, suffix: 'ms'),
          _number('To', _max, suffix: 'ms'),
        ],
        if (kind == MockScenarioKind.flaky) ...[
          _number('Every Nth', _every, width: 100),
          _number('or % fail', _percent, suffix: '%'),
          _number('Status', _status, width: 90),
        ],
        if (kind != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(_hint(_scenario!), style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
          ),
      ],
    );
  }

  String _hint(MockScenario s) => switch (s.kind) {
        MockScenarioKind.slow => s.latencyMinMs == s.latencyMaxMs ? 'Every answer waits ${s.latencyMinMs} ms.' : 'Every answer waits a random time from ${s.latencyMinMs} to ${s.latencyMaxMs} ms.',
        MockScenarioKind.flaky => s.failEvery > 0
            ? 'Every ${s.failEvery}${s.failEvery == 1 ? 'st' : s.failEvery == 2 ? 'nd' : s.failEvery == 3 ? 'rd' : 'th'} request answers ${s.failStatus}; the others are normal.'
            : '${s.failPercent}% of the requests answer ${s.failStatus}; the others are normal. (Every Nth wins when it is above 0.)',
        _ => s.kind.description,
      };
}

/// "When the request has this, answer with that saved example": rules for the routes of the collection.
class _MatchRules extends StatelessWidget {
  final MockServerViewModel vm;
  const _MatchRules({required this.vm});

  @override
  Widget build(BuildContext context) {
    final rules = vm.rules;
    final routes = vm.table.routes.where((r) => r.allExamples.length > 1).toList();
    final fromSpec = vm.source == MockSourceKind.openApi;
    return ToolSection(
      title: 'Pick a saved example by the request (${rules.length})',
      hint: 'A route with several saved examples answers the first successful one. Add ?status=404 or ?example=Name to a call to choose another, '
          'or set a rule here to choose by a query parameter, a header or a field of the JSON body.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fromSpec)
            const InfoBanner(message: 'Rules choose between saved examples. While the server serves an OpenAPI document there are none: switch the source back to use them.')
          else if (routes.isEmpty)
            const InfoBanner(message: 'No route has more than one saved example yet. Save a second response of a request (a 404, say) with "Save as example", then start the server or press Reload examples.'),
          for (final rule in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RuleRow(
                key: ValueKey(rule.id),
                rule: rule,
                routes: vm.table.routes,
                onChanged: (r) => vm.setRules([for (final x in rules) x.id == r.id ? r : x]),
                onRemove: () => vm.setRules([for (final x in rules) if (x.id != rule.id) x]),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: routes.isEmpty || fromSpec ? null : () => vm.setRules([...rules, _newRule(routes.first, rules)]),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add a rule'),
            ),
          ),
        ],
      ),
    );
  }

  MockMatchRule _newRule(MockRoute route, List<MockMatchRule> existing) {
    var n = existing.length + 1;
    while (existing.any((r) => r.id == 'rule-$n')) {
      n++;
    }
    return MockMatchRule(
      id: 'rule-$n',
      routeKey: route.key,
      source: MockMatchSource.query,
      field: '',
      equals: '',
      exampleName: route.allExamples.last.name,
    );
  }
}

class _RuleRow extends StatefulWidget {
  final MockMatchRule rule;
  final List<MockRoute> routes;
  final ValueChanged<MockMatchRule> onChanged;
  final VoidCallback onRemove;

  const _RuleRow({super.key, required this.rule, required this.routes, required this.onChanged, required this.onRemove});

  @override
  State<_RuleRow> createState() => _RuleRowState();
}

class _RuleRowState extends State<_RuleRow> {
  late MockMatchRule _rule = widget.rule;
  late final _field = TextEditingController(text: widget.rule.field);
  late final _equals = TextEditingController(text: widget.rule.equals);

  @override
  void dispose() {
    _field.dispose();
    _equals.dispose();
    super.dispose();
  }

  void _set(MockMatchRule rule) {
    setState(() => _rule = rule);
    widget.onChanged(rule);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final route = widget.routes.where((r) => r.key == _rule.routeKey).firstOrNull;
    final names = [for (final e in route?.allExamples ?? const <MockExample>[]) e.name];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              key: ValueKey('route-${_rule.routeKey}'),
              initialValue: widget.routes.any((r) => r.key == _rule.routeKey) ? _rule.routeKey : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'On route'),
              items: [for (final r in widget.routes) DropdownMenuItem(value: r.key, child: Text(r.key, overflow: TextOverflow.ellipsis))],
              onChanged: (key) {
                if (key == null) return;
                final next = widget.routes.firstWhere((r) => r.key == key);
                _set(_rule.copyWith(routeKey: key, exampleName: next.allExamples.last.name));
              },
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<MockMatchSource>(
              key: ValueKey('source-${_rule.source}'),
              initialValue: _rule.source,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'When the'),
              items: [for (final s in MockMatchSource.values) DropdownMenuItem(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis))],
              onChanged: (s) => s == null ? null : _set(_rule.copyWith(source: s)),
            ),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _field,
              autocorrect: false,
              decoration: InputDecoration(labelText: _rule.source == MockMatchSource.body ? 'Field (a.b.c)' : 'Name'),
              onChanged: (v) => _set(_rule.copyWith(field: v)),
            ),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _equals,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'equals'),
              onChanged: (v) => _set(_rule.copyWith(equals: v)),
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              key: ValueKey('example-${_rule.routeKey}-${_rule.exampleName}'),
              initialValue: names.contains(_rule.exampleName) ? _rule.exampleName : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'answer with'),
              items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n.isEmpty ? '(unnamed)' : n, overflow: TextOverflow.ellipsis))],
              onChanged: (n) => n == null ? null : _set(_rule.copyWith(exampleName: n)),
            ),
          ),
          IconButton(icon: const Icon(Icons.delete_outline, size: 18), tooltip: 'Remove this rule', onPressed: widget.onRemove),
        ],
      ),
    );
  }
}
