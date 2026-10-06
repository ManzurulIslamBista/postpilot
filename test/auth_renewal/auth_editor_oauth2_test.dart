// What the Auth tab shows and does for self-renewing auth: the token status, the Auto-renew switch, Renew now,
// the re-login section with its Test, the same status for an inherited OAuth 2.0, and the notes above a response.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/auth_owner.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/widgets/info_banner.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/relogin_config.dart';
import 'package:postpilot/features/auth_renewal/domain/services/oauth2_token_manager.dart';
import 'package:postpilot/features/auth_renewal/domain/usecases/relogin_usecase.dart';
import 'package:postpilot/features/auth_renewal/data/repository_oauth2_token_store.dart';
import 'package:postpilot/features/auth_renewal/presentation/view_models/inherited_oauth2_status_view_model.dart';
import 'package:postpilot/features/auth_renewal/presentation/view_models/relogin_section_view_model.dart';
import 'package:postpilot/features/auth_renewal/presentation/widgets/auth_notes_banner.dart';
import 'package:postpilot/features/auth_renewal/presentation/widgets/inherited_oauth2_status.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/defaults/presentation/view_models/inherited_defaults_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/services/oauth2_token_service.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/request_oauth2_view_model.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/auth_editor.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:provider/provider.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';
import 'auth_harness.dart';

void main() {
  late InMemoryDb db;
  late FakeAuthServer server;
  late int shop;
  late OAuth2TokenManager manager;

  setUp(() async {
    await locator.reset();
    db = InMemoryDb();
    server = FakeAuthServer();
    shop = await db.collectionRepository.createCollection('Shop');
    final resolver = BuildVariableResolverUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository);
    final service = OAuth2TokenService(server);
    manager = OAuth2TokenManager(
      service,
      RepositoryOAuth2TokenStore(db.requestRepository, db.collectionAuthRepository, db.defaultsRepository),
    );
    final scripts = RunRequestScriptsUseCase(db.scriptsRepository, resolver, db.environmentRepository, db.globalVariableRepository);
    final relogin = ReloginUseCase(db.requestRepository, db.collectionAuthRepository, scripts, collections: db.collectionRepository);
    final send = SendRequestUseCase(server, resolver, RecordingHistory(), db.collectionAuthRepository);
    locator
      ..registerFactory<RequestOAuth2ViewModel>(() => RequestOAuth2ViewModel(service, resolver, manager))
      ..registerFactory<ReloginSectionViewModel>(() => ReloginSectionViewModel(relogin, send))
      ..registerFactory<InheritedOAuth2StatusViewModel>(() => InheritedOAuth2StatusViewModel(manager, resolver));
  });
  tearDown(() => locator.reset());

  /// An [AuthEditor] that keeps the auth it is told about, as the dialog or the request tab does; [changes] is every edit.
  Future<List<RequestAuth>> pumpEditor(
    WidgetTester tester,
    RequestAuth initial, {
    bool showRelogin = false,
    bool allowInherit = false,
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final changes = <RequestAuth>[];
    var auth = initial;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => AuthEditor(
                auth: auth,
                allowInherit: allowInherit,
                collectionId: shop,
                showRelogin: showRelogin,
                onChanged: (next) => setState(() {
                  auth = next;
                  changes.add(next);
                }),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return changes;
  }

  bool autoRenewOn(WidgetTester tester) => tester.widget<SwitchListTile>(find.byKey(const ValueKey('oauth2-auto-renew'))).value;

  group('the token status and Auto-renew', () {
    testWidgets('says there is no token, that Auto-renew is on by default, and offers Renew now', (tester) async {
      await pumpEditor(tester, oauthAuth());

      expect(find.text('No token yet'), findsOneWidget);
      expect(find.text('Auto-renew'), findsOneWidget);
      expect(autoRenewOn(tester), isTrue);
      expect(find.textContaining('Auto-renew is on: before a send the token is renewed when it is missing or expires within 30 s'), findsOneWidget);
      expect(find.text('Renew now'), findsOneWidget);
    });

    testWidgets('switching Auto-renew off is an edit of the auth, and the line says what that means', (tester) async {
      final changes = await pumpEditor(tester, oauthAuth());

      await tester.tap(find.byKey(const ValueKey('oauth2-auto-renew')));
      await tester.pumpAndSettle();

      expect(changes.single.oauth2AutoRenew, isFalse);
      expect(autoRenewOn(tester), isFalse);
      expect(find.textContaining('Auto-renew is off: a token that is missing or expired is sent as it is'), findsOneWidget);
    });

    testWidgets('Renew now gets a token with the configured grant and hands it to the owner of the auth, status updated', (tester) async {
      final changes = await pumpEditor(tester, oauthAuth());

      await tester.tap(find.text('Renew now'));
      await tester.pumpAndSettle();

      expect(server.tokenCalls.single.grant, 'client_credentials');
      expect(changes.single.oauth2AccessToken, 'at-1');
      expect(find.textContaining(RegExp(r'Token valid for (59m|1h 0m)')), findsOneWidget);
      expect(find.text('No token yet'), findsNothing);
    });

    testWidgets('Renew now uses the refresh token when there is one', (tester) async {
      server
        ..rotateRefresh = true
        ..validRefresh.add('rt-old');
      final changes = await pumpEditor(tester, oauthAuth(token: 'old', expiry: DateTime.now().subtract(const Duration(hours: 1)), refresh: 'rt-old'));
      expect(find.text('Token expired'), findsOneWidget);

      await tester.tap(find.text('Renew now'));
      await tester.pumpAndSettle();

      expect(server.tokenCalls.single.grant, 'refresh_token');
      expect((changes.single.oauth2AccessToken, changes.single.oauth2RefreshToken), ('at-1', 'rt-1'));
    });

    testWidgets('clearing the token makes the manager forget what it renewed, so the next send fetches a new one', (tester) async {
      final owner = AuthOwner.collection(shop, 'Shop');
      final first = await manager.ensureFresh(oauthAuth(), owner: owner, resolver: VariableResolver(const {}));
      expect(server.tokenCalls, hasLength(1));
      await pumpEditor(tester, oauthAuth(token: first.auth.oauth2AccessToken, expiry: first.auth.oauth2TokenExpiry));

      await tester.tap(find.byTooltip('Clear token'));
      await tester.pumpAndSettle();
      final after = await manager.ensureFresh(oauthAuth(), owner: owner, resolver: VariableResolver(const {}));

      expect(find.text('No token yet'), findsOneWidget);
      expect(after.kind, TokenRenewalKind.fetched);
      expect(server.tokenCalls, hasLength(2));
    });

    testWidgets('a renewal that fails says which part to check, and shows no secret', (tester) async {
      final changes = await pumpEditor(tester, oauthAuth(secret: 'wrong-secret-9'));

      await tester.tap(find.text('Renew now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('rejected the client credentials'), findsOneWidget);
      // The (obscured) Client Secret field holds it, as it should; nothing the tab shows as text does.
      expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('wrong-secret-9')), findsNothing);
      expect(changes, isEmpty);
    });

    testWidgets('Authorization Code without a refresh token has no Renew now, and says why; with one it has', (tester) async {
      await pumpEditor(tester, oauthAuth(grant: OAuth2GrantType.authorizationCodePkce));
      expect(find.text('Renew now'), findsNothing);
      expect(find.textContaining('Authorization Code needs a browser'), findsOneWidget);
      expect(find.text('Get new access token (opens browser)'), findsOneWidget);

      await pumpEditor(
        tester,
        oauthAuth(grant: OAuth2GrantType.authorizationCodePkce, token: 'a', expiry: DateTime.now().add(const Duration(hours: 1)), refresh: 'r'),
      );
      expect(find.text('Renew now'), findsOneWidget);
    });
  });

  group('the re-login section', () {
    late int authFolder;

    setUp(() async {
      authFolder = await db.collectionRepository.createFolder(collectionId: shop, name: 'Auth');
      final login = await addRequest(db, shop, 'Login', folderId: authFolder, method: HttpMethod.post, url: '$apiHost/login');
      await db.scriptsRepository.save(RequestScriptsEntity(
        requestId: login,
        extractorsJson: ScriptsJsonCodec.encodeExtractors([ExtractorEntity(path: r'$.token', variableKey: 'token', scope: ExtractorScope.global)]),
      ));
      await addRequest(db, shop, 'Orders', url: '$apiHost/orders');
    });

    const bearer = RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}');

    testWidgets('is off until switched on, then proposes the request that looks like a login, with 401 and 403', (tester) async {
      final changes = await pumpEditor(tester, bearer, showRelogin: true);
      expect(find.text('Re-login on 401/403'), findsOneWidget);
      expect(find.byKey(const ValueKey('relogin-request')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('relogin-switch')));
      await tester.pumpAndSettle();

      expect(changes.single.relogin, const ReloginConfig(request: 'Auth/Login'));
      expect(find.byKey(const ValueKey('relogin-request')), findsOneWidget);
      expect(find.text('POST  Auth/Login'), findsOneWidget);
      expect(tester.widget<FilterChip>(find.byKey(const ValueKey('relogin-status-401'))).selected, isTrue);
      expect(tester.widget<FilterChip>(find.byKey(const ValueKey('relogin-status-403'))).selected, isTrue);
    });

    testWidgets('a status can be left out, but not both; switching off removes the setting', (tester) async {
      final changes = await pumpEditor(tester, bearer.withRelogin(const ReloginConfig(request: 'Auth/Login')), showRelogin: true);

      await tester.tap(find.byKey(const ValueKey('relogin-status-403')));
      await tester.pumpAndSettle();
      expect(changes.last.relogin!.statuses, {401});

      await tester.tap(find.byKey(const ValueKey('relogin-status-401')));
      await tester.pumpAndSettle();
      expect(changes.last.relogin!.statuses, {401}, reason: 'a setting that never runs is not offered');

      await tester.tap(find.byKey(const ValueKey('relogin-switch')));
      await tester.pumpAndSettle();
      expect(changes.last.relogin, isNull);
    });

    testWidgets('Test runs the login once and says which variable it saved', (tester) async {
      await pumpEditor(tester, bearer.withRelogin(const ReloginConfig(request: 'Auth/Login')), showRelogin: true);

      await tester.tap(find.byKey(const ValueKey('relogin-test')));
      await tester.pumpAndSettle();

      expect(find.text('Logged in via "Auth/Login". Saved {{token}}.'), findsOneWidget);
      expect(server.logins, 1);
      expect((await db.globalVariableRepository.getEnabledMap())['token'], 'login-1');
    });

    testWidgets('Test says why a login failed', (tester) async {
      server.apiOverride = (spec) => Uri.parse(spec.url).path == '/login' ? server.reply(401, {'error': 'bad'}) : null;
      await pumpEditor(tester, bearer.withRelogin(const ReloginConfig(request: 'Auth/Login')), showRelogin: true);

      await tester.tap(find.byKey(const ValueKey('relogin-test')));
      await tester.pumpAndSettle();

      expect(find.text('The login failed: it answered HTTP 401.'), findsOneWidget);
    });

    testWidgets('warns when the request it names is gone', (tester) async {
      await pumpEditor(tester, bearer.withRelogin(const ReloginConfig(request: 'Auth/Renamed')), showRelogin: true);

      expect(find.textContaining('No request is called "Auth/Renamed" in this collection'), findsOneWidget);
    });

    testWidgets('is not offered for a request, or for a folder that only inherits its auth', (tester) async {
      await pumpEditor(tester, bearer);
      expect(find.text('Re-login on 401/403'), findsNothing);

      await pumpEditor(tester, const RequestAuth(type: AuthType.inherit), showRelogin: true, allowInherit: true);
      expect(find.text('Re-login on 401/403'), findsNothing);
    });
  });

  group('a request that inherits OAuth 2.0', () {
    late InheritedDefaultsViewModel inherited;

    Future<void> pumpStatus(WidgetTester tester, RequestAuth requestAuth, {int? folderId}) async {
      inherited = InheritedDefaultsViewModel(ResolveRequestDefaultsUseCase(db.defaultsRepository));
      addTearDown(inherited.dispose);
      inherited.bind(shop, folderId: folderId);
      await tester.pump();
      await tester.pump();
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ChangeNotifierProvider<InheritedDefaultsViewModel>.value(
            value: inherited,
            child: Scaffold(body: InheritedOAuth2Status(requestAuth: requestAuth)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const inheriting = RequestAuth(type: AuthType.inherit);

    testWidgets('shows the status of the collection\'s token and where it is set, and renews it there', (tester) async {
      await db.collectionAuthRepository.setAuthJson(
        shop,
        oauthAuth(token: 'old', expiry: DateTime.now().add(const Duration(minutes: 12, seconds: 30))).toJsonString(),
      );
      await pumpStatus(tester, inheriting);

      expect(find.text('Token valid for 12m (collection "Shop")'), findsOneWidget);
      expect(find.textContaining('Auto-renew is on'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inherited-oauth2-renew')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(server.tokenCalls, hasLength(1));
      final stored = RequestAuth.fromJsonString(await db.collectionAuthRepository.getAuthJson(shop))!;
      expect(stored.oauth2AccessToken, 'at-1', reason: 'written where the auth is set, not onto the request');
    });

    testWidgets('a folder\'s OAuth 2.0 is shown with the folder named', (tester) async {
      final admin = await db.collectionRepository.createFolder(collectionId: shop, name: 'Admin');
      await db.defaultsRepository.saveFolder(admin, LevelDefaults(auth: oauthAuth()));
      await pumpStatus(tester, inheriting, folderId: admin);

      expect(find.text('No token yet (folder "Admin")'), findsOneWidget);
    });

    testWidgets('says Auto-renew is off when it is', (tester) async {
      await db.collectionAuthRepository.setAuthJson(shop, oauthAuth(autoRenew: false).toJsonString());
      await pumpStatus(tester, inheriting);

      expect(find.textContaining('Auto-renew is off'), findsOneWidget);
    });

    testWidgets('shows nothing for a request with an auth of its own, or an inherited auth that is not OAuth 2.0', (tester) async {
      await db.collectionAuthRepository.setAuthJson(shop, oauthAuth().toJsonString());
      await pumpStatus(tester, const RequestAuth(type: AuthType.bearer));
      expect(find.byKey(const ValueKey('inherited-oauth2-status')), findsNothing);

      await db.collectionAuthRepository.setAuthJson(shop, const RequestAuth(type: AuthType.bearer, bearerToken: 'x').toJsonString());
      await pumpStatus(tester, inheriting);
      expect(find.byKey(const ValueKey('inherited-oauth2-status')), findsNothing);
    });
  });

  group('the notes above a response', () {
    Future<void> pumpBanner(WidgetTester tester, List<String> notes) => tester.pumpWidget(
          MaterialApp(theme: AppTheme.light, home: Scaffold(body: AuthNotesBanner(notes: notes))),
        );

    testWidgets('are not there when nothing happened', (tester) async {
      await pumpBanner(tester, const []);

      expect(find.byType(InfoBanner), findsNothing);
    });

    testWidgets('list what the app did, as information when it worked and as a warning when it did not', (tester) async {
      await pumpBanner(tester, const ['Re-authenticated via "Auth/Login" and retried (the first answer was HTTP 401).']);
      expect(find.text('Re-authenticated via "Auth/Login" and retried (the first answer was HTTP 401).'), findsOneWidget);
      expect(tester.widget<InfoBanner>(find.byType(InfoBanner)).kind, BannerKind.info);

      await pumpBanner(tester, const ['Re-login via "Auth/Login" failed (it answered HTTP 500), so the request was not retried.']);
      expect(tester.widget<InfoBanner>(find.byType(InfoBanner)).kind, BannerKind.warning);
    });
  });
}
