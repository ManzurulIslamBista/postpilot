import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_json2.dart';
import 'package:postpilot/features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import 'package:postpilot/features/odoo/presentation/view_models/odoo_studio_view_model.dart';
import 'package:postpilot/features/odoo/presentation/widgets/odoo_connect_tab.dart';
import '../support/drift_repos.dart';

final class _RecordingApi implements ApiClient {
  final specs = <ApiRequestSpec>[];

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    specs.add(spec);
    return ApiHttpResponse(
      statusCode: 200,
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: utf8.encode('{"lang": "en_US"}'),
      duration: Duration.zero,
    );
  }
}

OdooConnection _c(String url) => OdooConnection(baseUrl: url, apiKey: 'k');

void main() {
  group('OdooConnection', () {
    test('adds https:// to a bare host and strips trailing slashes and spaces', () {
      expect(_c('myco.odoo.com').normalizedUrl, 'https://myco.odoo.com');
      expect(_c('  myco.odoo.com///  ').normalizedUrl, 'https://myco.odoo.com');
      expect(_c('http://localhost:8069/').normalizedUrl, 'http://localhost:8069');
      expect(_c('https://myco.odoo.com/').normalizedUrl, 'https://myco.odoo.com');
      expect(_c('').normalizedUrl, '');
    });

    test('warns about http:// only for hosts outside this computer and private networks', () {
      for (final url in ['http://myco.odoo.com', 'HTTP://Myco.Odoo.com/', 'http://8.8.8.8', 'http://172.32.0.1:8069', 'http://11.0.0.1']) {
        expect(_c(url).sendsKeyUnencrypted, isTrue, reason: url);
      }
      for (final url in [
        'myco.odoo.com',
        'https://myco.odoo.com',
        'http://localhost:8069',
        'http://odoo.localhost',
        'http://127.0.0.1:8069',
        'http://192.168.1.5:8069',
        'http://10.1.2.3',
        'http://172.16.0.9',
        'http://172.31.255.1',
        'http://[::1]:8069',
        'http://odoo',
        'http://server.local',
        '',
      ]) {
        expect(_c(url).sendsKeyUnencrypted, isFalse, reason: url);
      }
    });
  });

  test('a call never produces a double slash before /json/2', () async {
    final api = _RecordingApi();
    await OdooClient(api).call(_c('myco.odoo.com/'), const OdooCall(model: 'res.users', method: 'context_get'));
    expect(api.specs.single.url, 'https://myco.odoo.com/json/2/res.users/context_get');
  });

  group('saved environment', () {
    late AppDatabase db;
    late DriftRepos repos;
    late OdooStudioViewModel vm;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repos = DriftRepos(db);
      vm = OdooStudioViewModel(
        OdooClient(_RecordingApi()),
        repos.environmentRepository,
        CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository),
      );
    });
    tearDown(() async {
      vm.dispose();
      await db.close();
    });

    test('keeps the https:// URL Studio tested, so saved requests do not fall back to http://', () async {
      vm.setConnection(url: 'myco.odoo.com/', database: 'myco', apiKey: ' key ');
      final id = await vm.saveEnvironment('Odoo');
      expect(id, isNotNull);
      final vars = await repos.environmentRepository.getActiveVariables();
      expect(vars['odooUrl'], 'https://myco.odoo.com');
      expect(vars['odooApiKey'], 'key');

      // What the sender would build from a saved request's {{odooUrl}}.
      final draft = OdooJson2.draft(const OdooCall(model: 'res.partner', method: 'search_read'));
      expect(VariableResolver(vars).resolve(draft.url), 'https://myco.odoo.com/json/2/res.partner/search_read');
    });

    testWidgets('the Connect tab warns while the URL is plain http:// to a public host', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: OdooConnectTab(viewModel: vm))));
      const warning = 'This URL uses plain http://';
      expect(find.text(warning), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'http://myco.odoo.com');
      await tester.pump();
      expect(find.text(warning), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'http://localhost:8069');
      await tester.pump();
      expect(find.text(warning), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'myco.odoo.com');
      await tester.pump();
      expect(find.text(warning), findsNothing);
    });

    test('an explicit http:// URL is kept as typed (the Connect tab warns about it)', () async {
      vm.setConnection(url: 'http://192.168.1.20:8069/', apiKey: 'key');
      await vm.saveEnvironment('Lan');
      expect((await repos.environmentRepository.getActiveVariables())['odooUrl'], 'http://192.168.1.20:8069');
    });
  });
}
