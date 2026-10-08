// The screens of the CORS proxy: the web settings pane, the error help under a failed call, and the desktop dialog.
import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/cors_proxy/data/cors_proxy_engine.dart';
import 'package:postpilot/features/cors_proxy/data/cors_proxy_settings_store.dart';
import 'package:postpilot/features/cors_proxy/data/cors_proxy_tester.dart';
import 'package:postpilot/features/cors_proxy/domain/cors_proxy_settings.dart';
import 'package:postpilot/features/cors_proxy/presentation/cors_error_help.dart';
import 'package:postpilot/features/cors_proxy/presentation/cors_proxy_dialog.dart';
import 'package:postpilot/features/cors_proxy/presentation/cors_proxy_server_view_model.dart';
import 'package:postpilot/features/cors_proxy/presentation/cors_proxy_settings_pane.dart';
import 'package:postpilot/features/cors_proxy/presentation/cors_proxy_settings_view_model.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/presentation/view_models/settings_view_model.dart';
import 'package:postpilot/features/settings/presentation/widgets/settings_dialog.dart';
import 'package:provider/provider.dart';
import '../settings/fakes/fake_settings_repositories.dart';

const _hosted = 'https://manzurulislambista.github.io';

final class _MemoryStore implements CorsProxySettingsStore {
  CorsProxySettings saved;
  _MemoryStore([this.saved = const CorsProxySettings()]);

  @override
  Future<CorsProxySettings> load() async => saved;

  @override
  Future<void> saveEnabled(bool enabled) async => saved = saved.copyWith(enabled: enabled);

  @override
  Future<void> saveUrl(String url) async => saved = saved.copyWith(url: url);

  @override
  Future<void> saveToken(String token) async => saved = saved.copyWith(token: token);
}

/// Answers the health check with [json], or fails like a browser that cannot reach the address.
final class _Canned implements HttpClientAdapter {
  final String? json;
  _Canned(this.json);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = json;
    if (body == null) throw DioException(requestOptions: options, type: DioExceptionType.connectionError, message: 'XMLHttpRequest error.');
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

CorsProxySettingsViewModel _settingsVm({String? answer, String? pageOrigin, CorsProxySettings initial = const CorsProxySettings(), _MemoryStore? store}) {
  final vm = CorsProxySettingsViewModel(
    store ?? _MemoryStore(initial),
    pageOrigin: pageOrigin,
    tester: CorsProxyTester(adapter: _Canned(answer), probe: (_) async => false, pageOrigin: pageOrigin),
  );
  addTearDown(vm.dispose);
  return vm;
}

Future<void> _show(WidgetTester tester, Widget child, {required double width, ThemeData? theme, double height = 900}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A new key each time: a second pump of the same kind of widget would otherwise keep the first one's state.
  await tester.pumpWidget(MaterialApp(theme: theme ?? AppTheme.light, home: Scaffold(body: KeyedSubtree(key: UniqueKey(), child: child))));
  await tester.pump();
}

Widget _inScroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

/// A fake engine that listens on no port.
final class _FakeEngine implements CorsProxyEngine {
  final _events = StreamController<CorsProxyEvent>.broadcast();
  CorsProxyConfig? started;
  Object? failWith;
  int starts = 0;
  int stops = 0;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  int? get port => _running ? (started!.port == 0 ? 4321 : started!.port) : null;

  @override
  CorsProxyConfig? get config => started;

  @override
  Stream<CorsProxyEvent> get events => _events.stream;

  @override
  Future<void> start(CorsProxyConfig config) async {
    starts++;
    final failure = failWith;
    if (failure != null) throw failure;
    started = config;
    _running = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    _running = false;
  }

  @override
  Future<void> dispose() async {
    _running = false;
    await _events.close();
  }

  void emit(String path, int status, {String? error}) => _events.add(CorsProxyEvent(
        at: DateTime(2026, 10, 7),
        method: 'GET',
        host: 'api.example.com',
        path: path,
        status: status,
        duration: const Duration(milliseconds: 12),
        error: error,
      ));
}

void main() {
  tearDown(() => locator.reset());

  group('settings pane', () {
    for (final (themeName, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      for (final width in [1200.0, 420.0]) {
        testWidgets('is complete and does not overflow, $themeName, ${width.toInt()} px wide', (tester) async {
          final vm = _settingsVm();
          await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: vm)), width: width, theme: theme);

          expect(find.text('CORS proxy'), findsOneWidget);
          expect(find.widgetWithText(TextField, 'Proxy URL'), findsOneWidget);
          expect(find.widgetWithText(TextField, 'Token'), findsOneWidget);
          expect(find.text('Test connection'), findsOneWidget);
          expect(find.text('Generate a token'), findsOneWidget);
          expect(find.byType(Switch), findsOneWidget);
          expect(find.text('RUN IT ON THIS COMPUTER'), findsOneWidget);
          expect(find.text('DEPLOY YOUR OWN CORS PROXY (2 MINUTES)'), findsOneWidget);
          expect(find.textContaining('dart run bin/postpilot.dart proxy'), findsOneWidget);
          expect(find.textContaining('wrangler secret put POSTPILOT_TOKEN --name postpilot-cors-proxy'), findsOneWidget);
          expect(tester.takeException(), isNull);
          // Everything is reachable by scrolling, nothing is clipped.
          await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -2000));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('shows the saved choices, and saves what the person changes: switch, address, token', (tester) async {
      final store = _MemoryStore(const CorsProxySettings(enabled: true, url: 'http://localhost:9000', token: 'saved-token-123'));
      final vm = _settingsVm(store: store);
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: vm)), width: 1200);
      await tester.pump();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Proxy URL')).controller!.text, 'http://localhost:9000');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Token')).controller!.text, 'saved-token-123');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Token')).obscureText, isTrue, reason: 'a secret is hidden until asked');

      await tester.tap(find.byType(Switch));
      await tester.enterText(find.widgetWithText(TextField, 'Proxy URL'), 'localhost:8787');
      await tester.enterText(find.widgetWithText(TextField, 'Token'), 'another-token-456');
      await tester.pump();

      expect(vm.settings, const CorsProxySettings(url: 'localhost:8787', token: 'another-token-456'));
      expect(store.saved, vm.settings, reason: 'the token goes to the store (the secure storage), not to the workspace');
      expect(CorsProxySettings.parseUrl(vm.settings.url).toString(), 'http://localhost:8787', reason: 'a missing scheme means http');
    });

    testWidgets('an unusable address is said, and Test connection waits', (tester) async {
      final vm = _settingsVm(initial: const CorsProxySettings(url: 'ftp://nope'));
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: vm)), width: 1200);
      await tester.pump();

      expect(find.textContaining('Enter the address the proxy printed'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Test connection')).onPressed, isNull);
    });

    testWidgets('generates a token, shows the command with it only on request, and copies it', (tester) async {
      final vm = _settingsVm();
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: vm)), width: 1200);
      expect(find.text('Copy with my token'), findsNothing);

      await tester.tap(find.text('Generate a token'));
      await tester.pump();

      expect(vm.settings.token, hasLength(32));
      expect(find.text('Copy with my token'), findsOneWidget);
      expect(vm.command(withToken: true), endsWith('--token ${vm.settings.token}'));
      expect(vm.command(), isNot(contains('--token')));
    });

    testWidgets('a token the browser cannot send is reported, and is never put into the copied command', (tester) async {
      final vm = _settingsVm(initial: const CorsProxySettings(token: r'tökén;$(id)'));
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: vm)), width: 1200);

      expect(find.textContaining('visible ASCII'), findsOneWidget);
      expect(vm.command(withToken: true), isNot(contains('--token')));

      vm.setToken(r'abcdefgh;$(id)');
      await tester.pump();
      expect(find.textContaining('visible ASCII'), findsNothing, reason: 'a Worker secret may hold any visible character');
      expect(vm.command(withToken: true), isNot(contains('--token')), reason: 'but a shell would run it');

      vm.setToken('abcdefgh-1234');
      await tester.pump();
      expect(vm.command(withToken: true), endsWith('--token abcdefgh-1234'));
    });

    testWidgets('Test connection says Connected, or exactly what is wrong', (tester) async {
      final ok = _settingsVm(answer: '{"ok":true,"version":"1","allowedOrigin":null}', initial: const CorsProxySettings(token: 'token-123456'));
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: ok)), width: 1200);
      await tester.pump();

      await tester.tap(find.text('Test connection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Connected'), findsOneWidget);
      expect(find.textContaining('answered'), findsOneWidget);

      final down = _settingsVm(initial: const CorsProxySettings(token: 'token-123456'));
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: down)), width: 420);
      await tester.pump();
      await tester.tap(find.text('Test connection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Nothing answers at that address'), findsOneWidget);
      expect(find.textContaining('dart run bin/postpilot.dart proxy', findRichText: true), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a result is dropped when the choices change', (tester) async {
      final vm = _settingsVm(answer: '{"ok":true,"version":"1","allowedOrigin":null}');
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: vm)), width: 1200);
      await tester.tap(find.text('Test connection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Connected'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Token'), 'changed-token-1');
      await tester.pump();

      expect(find.text('Connected'), findsNothing);
    });

    testWidgets('on a hosted page the Worker comes first and the command allows that page', (tester) async {
      final vm = _settingsVm(pageOrigin: 'https://tools.example.com');
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: vm)), width: 1200);

      final deploy = tester.getTopLeft(find.text('DEPLOY YOUR OWN CORS PROXY (2 MINUTES)')).dy;
      final local = tester.getTopLeft(find.text('RUN IT ON THIS COMPUTER')).dy;
      expect(deploy, lessThan(local));
      expect(find.textContaining('--allow-origin https://tools.example.com'), findsWidgets);
      expect(find.textContaining('--var ALLOWED_ORIGINS:https://tools.example.com'), findsOneWidget);
      expect(find.textContaining('This page runs at https://tools.example.com'), findsOneWidget);
    });

    testWidgets('on the hosted app the Worker needs no variable, and on localhost the local proxy comes first', (tester) async {
      final hosted = _settingsVm(pageOrigin: _hosted);
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: hosted)), width: 1200);
      expect(find.textContaining('ALLOWED_ORIGINS'), findsNothing);

      final local = _settingsVm(pageOrigin: 'http://localhost:5000');
      await _show(tester, _inScroll(CorsProxySettingsPane(viewModel: local)), width: 1200);
      expect(
        tester.getTopLeft(find.text('RUN IT ON THIS COMPUTER')).dy,
        lessThan(tester.getTopLeft(find.text('DEPLOY YOUR OWN CORS PROXY (2 MINUTES)')).dy),
      );
      expect(find.textContaining('allows pages on this computer by default'), findsOneWidget);
    });
  });

  group('in the settings dialog', () {
    Future<void> open(WidgetTester tester, {required bool isWeb, bool corsProxy = false, double width = 1000}) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await locator.reset();
      locator.registerSingleton<CorsProxySettingsViewModel>(_settingsVm());
      final settings = SettingsViewModel(FakeSettingsRepository(const AppSettings()));
      addTearDown(settings.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<SettingsViewModel>.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(context: context, builder: (_) => SettingsDialog(isWeb: isWeb, openCorsProxy: corsProxy)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the browser version has a CORS proxy section, and can open on it', (tester) async {
      await open(tester, isWeb: true);
      expect(find.text('CORS proxy'), findsOneWidget, reason: 'the section, not selected');
      expect(find.text('Test connection'), findsNothing);

      await tester.tap(find.text('CORS proxy'));
      await tester.pumpAndSettle();
      expect(find.text('Test connection'), findsOneWidget);
      expect(find.text('CORS proxy'), findsNWidgets(2), reason: 'the section and the heading');
    });

    testWidgets('opens straight on the CORS proxy section when asked, also in a narrow window', (tester) async {
      await open(tester, isWeb: true, corsProxy: true, width: 420);

      expect(find.text('Test connection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the desktop and mobile apps have no such section, and asking for it opens General', (tester) async {
      await open(tester, isWeb: false, corsProxy: true);

      expect(find.text('CORS proxy'), findsNothing);
      expect(find.text('Test connection'), findsNothing);
      expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'General')).selected, isTrue, reason: 'General is shown');
    });
  });

  group('error help', () {
    for (final (themeName, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      testWidgets('a CORS block offers the proxy, the exact command and the desktop app, $themeName', (tester) async {
        var opened = 0;
        await _show(tester, CorsErrorHelp(help: NetworkHelp.corsBlocked, onOpenSettings: () => opened++), width: 420, theme: theme);

        expect(find.text('Use the CORS proxy'), findsOneWidget);
        expect(find.text('dart run bin/postpilot.dart proxy'), findsOneWidget);
        expect(find.textContaining('desktop app, which is not limited by CORS'), findsOneWidget);

        await tester.tap(find.text('Use the CORS proxy'));
        expect(opened, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a proxy that is on but cannot be used points at its settings, without the command', (tester) async {
      var opened = 0;
      await _show(tester, CorsErrorHelp(help: NetworkHelp.corsProxy, onOpenSettings: () => opened++), width: 1200);

      expect(find.text('Open the CORS proxy settings'), findsOneWidget);
      expect(find.text('Use the CORS proxy'), findsNothing);
      expect(find.text('dart run bin/postpilot.dart proxy'), findsNothing);

      await tester.tap(find.text('Open the CORS proxy settings'));
      expect(opened, 1);
    });
  });

  group('desktop view model', () {
    late _FakeEngine engine;
    late CorsProxyServerViewModel vm;

    setUp(() {
      engine = _FakeEngine();
      vm = CorsProxyServerViewModel(engineFactory: () => engine, supported: true);
      addTearDown(vm.dispose);
    });

    test('starts with the defaults: this computer only, port 8787, this session\'s token, no extra page', () async {
      await vm.start();

      expect(vm.isRunning, isTrue);
      expect(engine.started!.host, '127.0.0.1');
      expect(engine.started!.port, 8787);
      expect(engine.started!.token, vm.token);
      expect(engine.started!.allowedOrigins, isEmpty);
      expect(engine.started!.insecure, isFalse);
      expect(vm.url, 'http://localhost:8787');
    });

    test('passes the options on, and the engine\'s own port when 0 was asked for', () async {
      vm.update(port: '0', origins: 'https://a.example.com, https://B.example.com/', allowLan: true, insecure: true);

      await vm.start();

      expect(engine.started!.host, '0.0.0.0');
      expect(engine.started!.allowedOrigins, ['https://a.example.com', 'https://b.example.com']);
      expect(engine.started!.insecure, isTrue);
      expect(vm.port, 4321);
      expect(vm.url, 'http://localhost:4321');
    });

    test('refuses a bad port or a wildcard origin before anything starts', () async {
      vm.update(port: '99999');
      await vm.start();
      expect(vm.error, contains('0 to 65535'));

      vm.update(port: '8787', origins: '*');
      await vm.start();
      expect(vm.error, contains('wildcard'));
      expect(engine.starts, 0);
      expect(vm.isRunning, isFalse);
    });

    test('says why it could not start', () async {
      engine.failWith = StateError('Port 8787 is already in use or not allowed. Choose another port with --port.');

      await vm.start();

      expect(vm.isRunning, isFalse);
      expect(vm.error, contains('already in use'));
      expect(vm.isBusy, isFalse);
    });

    test('keeps the newest calls first, at most 200, and clears them at the next start', () async {
      await vm.start();
      for (var i = 0; i < 205; i++) {
        engine.emit('/call/$i', 200);
      }
      await pumpEventQueue();

      expect(vm.events, hasLength(CorsProxyServerViewModel.maxEvents));
      expect(vm.events.first.path, '/call/204');

      await vm.stop();
      await vm.start();
      expect(vm.events, isEmpty);
    });

    test('keeps its token across a restart, changes it only on request and only while stopped, and ignores edits while running', () async {
      final first = vm.token;
      await vm.start();
      vm.newToken();
      vm.update(port: '9999');
      expect(vm.token, first);
      expect(vm.portText, '8787');

      await vm.stop();
      expect(vm.isRunning, isFalse);
      expect(engine.stops, 1);
      await vm.start();
      expect(engine.started!.token, first);

      await vm.stop();
      vm.newToken();
      expect(vm.token, isNot(first));
    });

    test('does nothing where a port cannot be opened', () async {
      final unsupported = CorsProxyServerViewModel(engineFactory: () => engine, supported: false);
      addTearDown(unsupported.dispose);

      await unsupported.start();

      expect(unsupported.isSupported, isFalse);
      expect(engine.starts, 0);
    });
  });

  group('desktop dialog', () {
    for (final (themeName, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      for (final width in [1200.0, 420.0]) {
        testWidgets('starts, shows the URL and a hidden token, lists calls and stops, $themeName, ${width.toInt()} px wide', (tester) async {
          final engine = _FakeEngine();
          final vm = CorsProxyServerViewModel(engineFactory: () => engine, supported: true);
          addTearDown(vm.dispose);
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: CorsProxyDialog(viewModel: vm))));
          await tester.pump();

          expect(find.text('CORS proxy'), findsOneWidget);
          expect(find.text('Start'), findsOneWidget);
          expect(find.text('Stop'), findsNothing);

          await tester.ensureVisible(find.text('Start'));
          await tester.tap(find.text('Start'));
          await tester.pump();
          await tester.pump();

          expect(find.text('Running on :8787'), findsOneWidget);
          expect(find.text('http://localhost:8787'), findsOneWidget);
          expect(find.text(vm.token), findsNothing, reason: 'the token is hidden until asked');
          await tester.ensureVisible(find.text('Show token'));
          await tester.tap(find.text('Show token'));
          await tester.pump();
          expect(find.text(vm.token), findsOneWidget);
          expect(find.text('No call yet'), findsOneWidget);

          engine.emit('/users?page=2', 200);
          engine.emit('/boom', 502, error: 'upstream_refused');
          await tester.pump();
          await tester.pump();
          expect(find.textContaining('GET api.example.com/users?page=2 200 12 ms'), findsOneWidget);
          expect(find.textContaining('GET api.example.com/boom 502 12 ms  [upstream_refused]'), findsOneWidget);

          await tester.ensureVisible(find.text('Stop'));
          await tester.tap(find.text('Stop'));
          await tester.pump();
          await tester.pump();
          expect(find.text('Start'), findsOneWidget);
          expect(find.text('http://localhost:8787'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the other-devices switch warns, and the running dialog repeats the warning', (tester) async {
      final engine = _FakeEngine();
      final vm = CorsProxyServerViewModel(engineFactory: () => engine, supported: true);
      addTearDown(vm.dispose);
      await _show(tester, CorsProxyDialog(viewModel: vm), width: 1200, height: 1000);

      await tester.tap(find.text('Allow other devices on my network'));
      await tester.pump();
      expect(vm.allowLan, isTrue);
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Open to your network'), findsOneWidget);
      expect(engine.started!.host, '0.0.0.0');
    });

    testWidgets('in a browser it says a port cannot be opened', (tester) async {
      final vm = CorsProxyServerViewModel(engineFactory: _FakeEngine.new, supported: false);
      addTearDown(vm.dispose);
      await _show(tester, CorsProxyDialog(viewModel: vm), width: 1200);

      expect(find.text('Not available in the browser'), findsOneWidget);
      expect(find.text('Start'), findsNothing);
    });
  });
}
