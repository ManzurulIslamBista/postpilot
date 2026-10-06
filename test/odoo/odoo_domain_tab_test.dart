import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/widgets/code_block.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import 'package:postpilot/features/odoo/presentation/view_models/odoo_studio_view_model.dart';
import 'package:postpilot/features/odoo/presentation/widgets/odoo_domain_tab.dart';
import '../support/drift_repos.dart';

final class _NoNetwork implements ApiClient {
  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async => throw 'offline in tests';
}

const _partnerFields = '''
{
  "name": {"type": "char", "string": "Name"},
  "parent_id": {"type": "many2one", "string": "Related Company", "relation": "res.partner"},
  "active": {"type": "boolean", "string": "Active"}
}
''';

void main() {
  late AppDatabase db;
  late OdooStudioViewModel vm;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final repos = DriftRepos(db);
    vm = OdooStudioViewModel(
      OdooClient(_NoNetwork()),
      repos.environmentRepository,
      CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository),
    );
  });
  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  /// The domain the tab writes for [domainText]: the JSON panel and the Python panel.
  Future<({Object? json, String python})> shown(WidgetTester tester, String domainText) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    vm.setDomainText(domainText);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: OdooDomainTab(viewModel: vm))));
    await tester.pump();
    final blocks = tester.widgetList<CodeBlock>(find.byType(CodeBlock)).toList();
    return (json: jsonDecode(blocks[0].text), python: blocks[1].text);
  }

  testWidgets('a value with brackets and quotes loads unchanged', (tester) async {
    final out = await shown(tester, r'''[('name', '=', "Acme (EU) [x] it's")]''');
    expect(out.json, [
      ['name', '=', "Acme (EU) [x] it's"],
    ]);
    expect(out.python, r"[('name', '=', 'Acme (EU) [x] it\'s')]");
  });

  testWidgets('False on a many2one stays False, not the text "false"', (tester) async {
    vm.useFieldsJson('res.partner', _partnerFields);
    final out = await shown(tester, "[('parent_id', '=', False)]");
    expect(out.json, [
      ['parent_id', '=', false],
    ]);
    expect(out.python, "[('parent_id', '=', False)]");
  });

  testWidgets('None and a list value survive, with and without the model loaded', (tester) async {
    final out = await shown(tester, "[('parent_id', '=', None), ('id', 'in', [1, 2, 3])]");
    expect(out.json, [
      '&',
      ['parent_id', '=', null],
      ['id', 'in', [1, 2, 3]],
    ]);
  });

  testWidgets('a negated group is kept, not turned into a blank row', (tester) async {
    final out = await shown(tester, "['!', '|', ('state', '=', 'draft'), ('state', '=', 'cancel')]");
    expect(out.json, [
      '!',
      '|',
      ['state', '=', 'draft'],
      ['state', '=', 'cancel'],
    ]);
    expect(out.python, "['!', '|', ('state', '=', 'draft'), ('state', '=', 'cancel')]");
    // The group shows its NOT switch turned on.
    final chip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'NOT').first);
    expect(chip.selected, isTrue);
  });

  testWidgets('a negated condition inside an OR group and a double negation', (tester) async {
    final out = await shown(tester, "['&', '!', '!', ('a', '=', 1), '|', ('b', '=', 2), '!', ('c', '=', 3)]");
    expect(out.json, [
      '&',
      '!',
      '!',
      ['a', '=', 1],
      '|',
      ['b', '=', 2],
      '!',
      ['c', '=', 3],
    ]);
  });

  testWidgets('an empty negated group writes nothing instead of a dangling "!"', (tester) async {
    final out = await shown(tester, '');
    expect(out.json, isEmpty);
    await tester.tap(find.text('Group'));
    await tester.pump();
    final notChips = find.widgetWithText(FilterChip, 'NOT');
    // In tree order: the first condition row's chip, then the new group's, then the group's own row.
    await tester.tap(notChips.at(1));
    await tester.pump();
    final blocks = tester.widgetList<CodeBlock>(find.byType(CodeBlock)).toList();
    expect(jsonDecode(blocks[0].text), isEmpty);
  });
}
