// The HMAC part of the Auth tab: the preset picker, the fields, the live signature preview, and that all of it
// fits at 1200 px and 420 px in the light and the dark theme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/usecases/list_variables_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/variable_scope.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/auth_editor.dart';
import 'package:provider/provider.dart';
import '../support/in_memory_import_export_fakes.dart';

// python: hmac.new(b"It's a Secret to Everybody", b'Hello, World!', sha256).hexdigest(), GitHub's own test vector
const _githubVector = '757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17';
// python: hmac.new(b'hunter2', b'{"a":1}', sha256).hexdigest()
const _hunter2 = '6e73a1a57a6e6edb9dff174d2a53bc61a27cfc639a2964743ed35fd59c8bc82d';

const _desktop = Size(1200, 900);
const _phone = Size(420, 900);

ApiRequestEntity _request({RequestBody body = const RequestBody(type: BodyType.raw, rawText: '{"a":1}'), RequestAuth auth = const RequestAuth()}) =>
    ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: 'hook',
      method: HttpMethod.post,
      url: 'https://api.example.com/hooks/in',
      headers: const [],
      queryParams: const [],
      body: body,
      auth: auth,
    );

/// An [AuthEditor] that keeps the auth it is told about, as the request tab does; the result is every edit.
Future<List<RequestAuth>> _pump(
  WidgetTester tester,
  RequestAuth initial, {
  Size size = _desktop,
  bool dark = false,
  ApiRequestEntity? request,
  VariableScope? scope,
  bool allowInherit = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final changes = <RequestAuth>[];
  var auth = initial;
  Widget editor = StatefulBuilder(
    builder: (context, setState) => AuthEditor(
      auth: auth,
      allowInherit: allowInherit,
      previewRequest: request,
      onChanged: (next) => setState(() {
        auth = next;
        changes.add(next);
      }),
    ),
  );
  if (scope != null) editor = ChangeNotifierProvider<VariableScope>.value(value: scope, child: editor);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: editor)),
    ),
  );
  await tester.pumpAndSettle();
  return changes;
}

String _text(WidgetTester tester, String key) => tester
    .widget<EditableText>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)))
    .controller
    .text;

Future<void> _choose(WidgetTester tester, Type dropdown, String label) async {
  await tester.tap(find.byType(dropdown));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('the type list and the fields', () {
    testWidgets('HMAC signature is one of the auth types, and choosing it shows its fields', (tester) async {
      final changes = await _pump(tester, const RequestAuth(type: AuthType.none));

      await tester.tap(find.byType(DropdownButton<AuthType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HMAC signature').last);
      await tester.pumpAndSettle();

      expect(changes.single.type, AuthType.hmac);
      for (final label in ['Provider preset', 'Secret', 'Algorithm', 'Encoding', 'Signed payload', 'Signature header', 'Header value', 'Signature preview']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('GitHub webhook'), findsOneWidget);
      expect(_text(tester, 'hmac-header-name-0'), 'X-Hub-Signature-256');
    });

    testWidgets('the secret is masked', (tester) async {
      await _pump(tester, const RequestAuth(type: AuthType.hmac, hmacSecret: 'whsec_visible?'));

      final secret = tester.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey('hmac-secret-0')), matching: find.byType(EditableText)));

      expect(secret.obscureText, isTrue);
      final others = find.descendant(of: find.byKey(const ValueKey('hmac-signature-preview')), matching: find.textContaining('whsec_visible?'));
      expect(others, findsNothing, reason: 'the preview does not show it');
    });

    testWidgets('a fixed timestamp has a field of its own, the current time does not', (tester) async {
      final changes = await _pump(tester, const RequestAuth(type: AuthType.hmac));
      expect(find.byKey(const ValueKey('hmac-timestamp-value-0')), findsNothing);

      await _choose(tester, DropdownButton<HmacTimestampSource>, 'Fixed value');

      expect(changes.last.hmacTimestampSource, HmacTimestampSource.fixed);
      expect(find.byKey(const ValueKey('hmac-timestamp-value-0')), findsOneWidget);
    });
  });

  group('presets', () {
    testWidgets('picking a preset fills the fields in and keeps the secret', (tester) async {
      final changes = await _pump(tester, const RequestAuth(type: AuthType.hmac, hmacSecret: 'keep-me'));

      await _choose(tester, DropdownButton<HmacPreset>, 'Stripe webhook');

      expect(changes.last.hmacPreset, HmacPreset.stripe);
      expect(changes.last.hmacSecret, 'keep-me');
      expect(_text(tester, 'hmac-header-name-1'), 'Stripe-Signature');
      expect(_text(tester, 'hmac-header-value-1'), 't={timestamp},v1={signature}');
      expect(_text(tester, 'hmac-payload-1'), '{timestamp}.{body}');
      expect(_text(tester, 'hmac-secret-1'), 'keep-me');
    });

    testWidgets('Slack fills in the timestamp header too, and GitHub takes it away again', (tester) async {
      await _pump(tester, const RequestAuth(type: AuthType.hmac));

      await _choose(tester, DropdownButton<HmacPreset>, 'Slack request');
      expect(_text(tester, 'hmac-timestamp-header-1'), 'X-Slack-Request-Timestamp');
      expect(_text(tester, 'hmac-payload-1'), 'v0:{timestamp}:{body}');

      await _choose(tester, DropdownButton<HmacPreset>, 'GitHub webhook');
      expect(_text(tester, 'hmac-timestamp-header-2'), isEmpty);
      expect(_text(tester, 'hmac-header-name-2'), 'X-Hub-Signature-256');
    });

    testWidgets('Generic keeps the values of the preset it was switched from', (tester) async {
      final changes = await _pump(tester, const RequestAuth(type: AuthType.hmac));
      await _choose(tester, DropdownButton<HmacPreset>, 'Shopify webhook');

      await _choose(tester, DropdownButton<HmacPreset>, 'Generic (custom)');

      expect(changes.last.hmacPreset, HmacPreset.generic);
      expect(changes.last.hmacHeaderName, 'X-Shopify-Hmac-Sha256');
      expect(changes.last.hmacEncoding, HmacEncoding.base64);
      expect(_text(tester, 'hmac-header-name-2'), 'X-Shopify-Hmac-Sha256');
    });

    testWidgets('editing a field of a preset makes it Generic, and typing keeps the field and its focus', (tester) async {
      final changes = await _pump(tester, const RequestAuth(type: AuthType.hmac));

      await tester.enterText(find.byKey(const ValueKey('hmac-header-name-0')), 'X-Signature');
      await tester.pump();

      expect(changes.last.hmacPreset, HmacPreset.generic);
      expect(changes.last.hmacHeaderName, 'X-Signature');
      expect(find.text('Generic (custom)'), findsOneWidget);
      expect(find.byKey(const ValueKey('hmac-header-name-0')), findsOneWidget, reason: 'the field was not replaced');

      await tester.enterText(find.byKey(const ValueKey('hmac-header-name-0')), 'X-Signature-2');
      await tester.pump();
      expect(changes.last.hmacHeaderName, 'X-Signature-2');
    });

    testWidgets('changing the secret or the timestamp source does not leave the preset', (tester) async {
      final changes = await _pump(tester, const RequestAuth(type: AuthType.hmac));

      await tester.enterText(find.byKey(const ValueKey('hmac-secret-0')), 'typed');
      await tester.pump();

      expect(changes.last.hmacPreset, HmacPreset.github);
      expect(changes.last.hmacSecret, 'typed');
    });
  });

  group('the signature preview', () {
    testWidgets('shows the GitHub test vector for the body of the request', (tester) async {
      await _pump(
        tester,
        const RequestAuth(type: AuthType.hmac, hmacSecret: "It's a Secret to Everybody"),
        request: _request(body: const RequestBody(type: BodyType.raw, rawText: 'Hello, World!')),
      );

      expect(find.text('X-Hub-Signature-256'), findsWidgets);
      expect(find.text('sha256=$_githubVector'), findsOneWidget);
      expect(find.text(_githubVector), findsOneWidget);
      expect(find.text('Hello, World!'), findsOneWidget, reason: 'the signed payload is shown');
      expect(find.textContaining('13 bytes'), findsOneWidget);
    });

    testWidgets('follows what is typed into the secret', (tester) async {
      await _pump(tester, const RequestAuth(type: AuthType.hmac), request: _request());
      expect(find.text('sha256=$_hunter2'), findsNothing);
      expect(find.textContaining('The secret is empty'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('hmac-secret-0')), 'hunter2');
      await tester.pump();

      expect(find.text('sha256=$_hunter2'), findsOneWidget);
      expect(find.textContaining('The secret is empty'), findsNothing);
    });

    testWidgets('selectable, not editable', (tester) async {
      await _pump(tester, const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2'), request: _request());

      final preview = find.byKey(const ValueKey('hmac-signature-preview'));

      expect(find.descendant(of: preview, matching: find.byType(SelectableText)), findsWidgets);
      expect(find.descendant(of: preview, matching: find.byType(TextField)), findsNothing);
    });

    testWidgets('Stripe: says that the timestamp is the clock', (tester) async {
      await _pump(
        tester,
        const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2'),
        request: _request(),
      );
      await _choose(tester, DropdownButton<HmacPreset>, 'Stripe webhook');

      expect(find.textContaining('is the current time: the signature changes on every send'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^t=\d{10},v1=[0-9a-f]{64}$')), findsOneWidget);
    });

    testWidgets('a fixed timestamp repeats the signature exactly', (tester) async {
      // python: hmac.new(b'hunter2', b'1700000000.{"a":1}', sha256).hexdigest()
      await _pump(
        tester,
        const RequestAuth(
          type: AuthType.hmac,
          hmacSecret: 'hunter2',
          hmacPreset: HmacPreset.stripe,
          hmacPayloadTemplate: '{timestamp}.{body}',
          hmacHeaderName: 'Stripe-Signature',
          hmacHeaderTemplate: 't={timestamp},v1={signature}',
          hmacTimestampSource: HmacTimestampSource.fixed,
          hmacTimestampValue: '1700000000',
        ),
        request: _request(),
      );

      expect(
        find.text('t=1700000000,v1=56b25cbf563812b38800e5f4dd1febfde087d36841155e70b3aa285517e1570a'),
        findsOneWidget,
      );
      expect(find.text('Timestamp 1700000000 (fixed).'), findsOneWidget);
    });

    testWidgets('a body that sends a file says it cannot be signed', (tester) async {
      await _pump(
        tester,
        const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2'),
        request: _request(
          body: const RequestBody(type: BodyType.binary).withBinaryFile(
            KeyValueItem(key: '', value: 'C:/files/a.bin', kind: FormFieldKind.file),
          ),
        ),
      );

      expect(find.textContaining('cannot sign a body that sends a file'), findsOneWidget);
      final preview = find.byKey(const ValueKey('hmac-signature-preview'));
      expect(find.descendant(of: preview, matching: find.byType(SelectableText)), findsNothing, reason: 'no signature is shown');
    });

    testWidgets('without a request it signs a sample body typed in', (tester) async {
      await _pump(tester, const RequestAuth(type: AuthType.hmac, hmacSecret: "It's a Secret to Everybody"));
      expect(find.byKey(const ValueKey('hmac-sample-body')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('hmac-sample-body')), 'Hello, World!');
      await tester.pump();

      expect(find.text('sha256=$_githubVector'), findsOneWidget);
    });

    testWidgets('a request has no sample body field', (tester) async {
      await _pump(tester, const RequestAuth(type: AuthType.hmac), request: _request());

      expect(find.byKey(const ValueKey('hmac-sample-body')), findsNothing);
    });

    testWidgets('no header name: says nothing would be sent', (tester) async {
      await _pump(tester, const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2', hmacHeaderName: ''), request: _request());

      expect(find.textContaining('No header name is set'), findsOneWidget);
    });

    testWidgets('the secret may be a variable of the environment in use, and an undefined one is pointed out', (tester) async {
      final db = InMemoryDb();
      final envId = db.nextId();
      db.environments.add(EnvironmentEntity(id: envId, name: 'Testing', isActive: true));
      db.environmentVariables.add(
        EnvironmentVariableEntity(id: db.nextId(), environmentId: envId, key: 'whsec', value: 'hunter2', isSecret: true, enabled: true),
      );
      final scope = VariableScope(ListVariablesUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository));
      addTearDown(scope.dispose);
      await tester.runAsync(() async {
        scope.bindCollection(1);
        await scope.refresh();
      });
      await _pump(tester, const RequestAuth(type: AuthType.hmac, hmacSecret: '{{whsec}}'), request: _request(), scope: scope);

      expect(find.text('sha256=$_hunter2'), findsOneWidget);
      expect(find.textContaining('Not defined'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('hmac-secret-0')), '{{nope}}');
      await tester.pump();

      expect(find.text('sha256=$_hunter2'), findsNothing);
      expect(find.textContaining('Not defined: {{nope}}'), findsOneWidget);
    });
  });

  group('the layout', () {
    // Everything the section can show at once: the longest signature (HMAC-SHA512 in hex), long templates and
    // names, a fixed timestamp, and a long body.
    const crowded = RequestAuth(
      type: AuthType.hmac,
      hmacPreset: HmacPreset.generic,
      hmacSecret: 'a-very-long-signing-secret-that-goes-on-and-on-0123456789',
      hmacAlgorithm: HmacAlgorithm.sha512,
      hmacPayloadTemplate: '{method} {path}?{query} {url} {timestamp} {body} and a good deal more text to wrap around',
      hmacHeaderName: 'X-A-Header-Name-That-Is-Quite-Long-Indeed',
      hmacHeaderTemplate: 'version=2;timestamp={timestamp};signature={signature};and=more',
      hmacTimestampHeader: 'X-Another-Quite-Long-Timestamp-Header-Name',
      hmacTimestampSource: HmacTimestampSource.fixed,
      hmacTimestampValue: '1700000000',
    );
    final longBody = RequestBody(type: BodyType.raw, rawText: '{"items":[${List.generate(120, (i) => '{"id":$i,"name":"Item number $i"}').join(',')}]}');

    for (final size in [_desktop, _phone]) {
      for (final dark in [false, true]) {
        final where = '${size.width.toInt()} px, ${dark ? 'dark' : 'light'}';

        testWidgets('a request with a crowded configuration fits at $where', (tester) async {
          await _pump(tester, crowded, size: size, dark: dark, request: _request(body: longBody));

          expect(tester.takeException(), isNull);
          expect(find.text('Signature preview'), findsOneWidget);
          expect(find.byKey(const ValueKey('hmac-timestamp-value-0')), findsOneWidget);
        });

        testWidgets('a collection\'s auth, with the sample body field, fits at $where', (tester) async {
          await _pump(tester, crowded, size: size, dark: dark);
          await tester.enterText(find.byKey(const ValueKey('hmac-sample-body')), 'line one\nline two\n' * 6);
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('hmac-sample-body')), findsOneWidget);
        });

        testWidgets('the plain default, and the message of a file body, fit at $where', (tester) async {
          await _pump(tester, const RequestAuth(type: AuthType.hmac), size: size, dark: dark, request: _request());
          expect(tester.takeException(), isNull);

          await _pump(
            tester,
            const RequestAuth(type: AuthType.hmac),
            size: size,
            dark: dark,
            request: _request(
              body: const RequestBody(type: BodyType.binary).withBinaryFile(
                KeyValueItem(key: '', value: 'C:/files/a.bin', kind: FormFieldKind.file),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.textContaining('cannot sign a body that sends a file'), findsOneWidget);
        });

        testWidgets('opening the preset list and picking one fits at $where', (tester) async {
          await _pump(tester, const RequestAuth(type: AuthType.hmac), size: size, dark: dark, request: _request());

          await _choose(tester, DropdownButton<HmacPreset>, 'Slack request');

          expect(tester.takeException(), isNull);
          expect(find.text('Slack request'), findsOneWidget);
        });
      }
    }
  });
}
