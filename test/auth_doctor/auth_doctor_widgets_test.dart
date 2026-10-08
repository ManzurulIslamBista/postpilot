// The doctor's dialog and banner, opened for real in a light and a dark theme at the width of a desktop window and of a phone. Flutter turns
// a layout overflow into a test failure, so this is what proves they fit, not just compile.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_doctor_input.dart';
import 'package:postpilot/features/auth_doctor/domain/usecases/build_auth_doctor_input_usecase.dart';
import 'package:postpilot/features/auth_doctor/presentation/auth_doctor_banner.dart';
import 'package:postpilot/features/auth_doctor/presentation/auth_doctor_dialog.dart';
import 'package:postpilot/features/auth_doctor/presentation/auth_doctor_launcher.dart';
import 'package:postpilot/features/auth_doctor/presentation/auth_doctor_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/response_tools/domain/services/response_history.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'auth_doctor_fixtures.dart';

final class _Fixed implements UseCase<AuthDoctorInput, AuthDoctorSubject> {
  final AuthDoctorInput? input;
  final Object? failure;
  int calls = 0;
  _Fixed(this.input, {this.failure});

  @override
  Future<AuthDoctorInput> call(AuthDoctorSubject params) async {
    calls++;
    if (failure != null) throw failure!;
    return input!;
  }
}

/// Opening a tab in the shell only watches the request; nothing else of the repository is used.
final class _Requests implements RequestRepository {
  @override
  Stream<ApiRequestEntity?> watchById(int id) => const Stream<ApiRequestEntity?>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

ApiRequestEntity _request() => ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: 'List orders',
      method: HttpMethod.get,
      url: 'https://api.example.com/v1/orders?api_key=k_0123456789abcdef',
      headers: const [],
      queryParams: const [],
      body: RequestBody.empty,
      auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
    );

ApiResponseEntity _response(int status, {String message = ''}) => ApiResponseEntity(
      statusCode: status,
      statusMessage: message,
      headers: const {'content-type': 'application/json'},
      bodyBytes: Uint8List.fromList(utf8.encode('{"error":"x"}')),
      duration: const Duration(milliseconds: 87),
    );

AuthDoctorSubject _subject(int status, {String message = 'Unauthorized'}) =>
    AuthDoctorSubject(request: _request(), response: _response(status, message: message));

/// An expired token against a production host with a staging environment: four findings across all three levels.
AuthDoctorInput _rich() {
  final token = jwt({'sub': 'u1', 'exp': epoch(clock) - 3 * 3600, 'aud': 'https://api.other.com'});
  return rejected(
    url: 'https://prod.example.com/v1/orders',
    headers: {'Authorization': 'Bearer $token'},
    headerTemplates: const {'Authorization': 'Bearer {{token}}'},
    environment: 'Staging',
    variables: const {'token': AuthVariableFact(name: 'token', scopeName: 'Staging')},
    responseHeaders: const {'WWW-Authenticate': 'Bearer realm="api", error="invalid_token", error_description="The access token expired"'},
  );
}

Future<void> _open(WidgetTester tester, {required double width, required bool dark, required AuthDoctorInputBuilder builder, int status = 401}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => AuthDoctorDialog.show(context, subject: _subject(status), builder: builder),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the dialog', () {
    for (final (width, dark) in [(1200.0, false), (1200.0, true), (420.0, false), (420.0, true)]) {
      testWidgets('lists the findings with their confidence at ${width.round()} px, ${dark ? 'dark' : 'light'}, without overflow', (tester) async {
        await _open(tester, width: width, dark: dark, builder: _Fixed(_rich()));

        expect(tester.takeException(), isNull);
        expect(find.text('Why was I rejected?'), findsOneWidget);
        expect(find.text('The token has expired'), findsOneWidget);
        expect(find.text('Certain'), findsOneWidget);
        expect(find.text('Likely'), findsWidgets);
        expect(find.textContaining('What to do: '), findsWidgets);
        expect(find.text('401 Unauthorized'), findsWidgets);
        expect(find.text('3 findings'), findsOneWidget);
        // The evidence shows the start of the token and its length, as the first card is on screen.
        expect(find.textContaining('eyJh… ('), findsWidgets);
      });
    }

    testWidgets('scrolls down to the evidence and to the plain-text copy, and the copy holds no token', (tester) async {
      await _open(tester, width: 420, dark: false, builder: _Fixed(_rich()));

      await tester.scrollUntilVisible(find.text('DIAGNOSIS'), 400, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('DIAGNOSIS'), findsOneWidget);
    });

    testWidgets('a response that was no refusal says so instead of listing nothing', (tester) async {
      await _open(tester, width: 800, dark: false, status: 200, builder: _Fixed(rejected(status: 200)));

      expect(tester.takeException(), isNull);
      expect(find.text('Nothing was rejected'), findsOneWidget);
    });

    testWidgets('a request that could not be rebuilt carries a warning', (tester) async {
      await _open(tester, width: 800, dark: false, builder: _Fixed(rejected(requestKnown: false)));

      expect(find.textContaining('could not be rebuilt as it was sent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an error while gathering is shown, not thrown', (tester) async {
      await _open(tester, width: 800, dark: true, builder: _Fixed(null, failure: StateError('the store is gone')));

      expect(tester.takeException(), isNull);
      expect(find.text('The doctor could not run'), findsOneWidget);
      expect(find.textContaining('the store is gone'), findsOneWidget);
    });
  });

  group('the banner', () {
    Future<void> pumpBanner(WidgetTester tester, ApiResponseEntity response, _Fixed builder, {double width = 800, bool dark = false}) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(body: Column(children: [AuthDoctorBanner(response: response, request: _request(), builder: builder)])),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('reads "Why was I rejected? - N findings" for a 401, and opens the doctor', (tester) async {
      final builder = _Fixed(_rich());
      await pumpBanner(tester, _response(401, message: 'Unauthorized'), builder);

      expect(find.text('Why was I rejected? - 3 findings'), findsOneWidget);

      await tester.tap(find.text('Why was I rejected? - 3 findings'));
      await tester.pumpAndSettle();

      expect(find.text('The token has expired'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says "1 finding" in the singular, fits a phone in the dark, and covers 403 and 407 too', (tester) async {
      for (final status in [403, 407]) {
        final one = _Fixed(rejected(status: status, headers: const {'Accept': '*/*'}, authType: AuthType.none));
        await pumpBanner(tester, _response(status), one, width: 360, dark: true);

        expect(find.text('Why was I rejected? - 1 finding'), findsOneWidget, reason: '$status');
        expect(tester.takeException(), isNull, reason: '$status');
      }
    });

    testWidgets('shows nothing for a response that worked, and does no work for it', (tester) async {
      final builder = _Fixed(_rich());
      await pumpBanner(tester, _response(200, message: 'OK'), builder);

      expect(find.textContaining('Why was I rejected?'), findsNothing);
      expect(builder.calls, 0);
    });

    testWidgets('a 400 appears only when its body talks about the token', (tester) async {
      ApiResponseEntity bad(String body) => ApiResponseEntity(
            statusCode: 400,
            statusMessage: 'Bad Request',
            headers: const {},
            bodyBytes: Uint8List.fromList(utf8.encode(body)),
            duration: Duration.zero,
          );
      await pumpBanner(tester, bad('{"error":"invalid_token"}'), _Fixed(rejected(status: 400, body: '{"error":"invalid_token"}')));
      expect(find.textContaining('Why was I rejected?'), findsOneWidget);

      await pumpBanner(tester, bad('{"error":"name is required"}'), _Fixed(rejected(status: 400)));
      expect(find.textContaining('Why was I rejected?'), findsNothing);
    });

    testWidgets('still opens the doctor when the count could not be worked out', (tester) async {
      await pumpBanner(tester, _response(401), _Fixed(null, failure: StateError('x')));

      expect(find.text('Why was I rejected?'), findsOneWidget);
    });
  });

  group('the command palette entry', () {
    late ShellViewModel shell;
    late ResponseHistory history;

    setUp(() async {
      await locator.reset();
      shell = ShellViewModel(_Requests());
      history = ResponseHistory();
      locator
        ..registerSingleton<ShellViewModel>(shell)
        ..registerSingleton<ResponseHistory>(history);
    });

    tearDown(() async {
      shell.dispose();
      await locator.reset();
    });

    test('is listed only while the open request has a rejected response in memory', () {
      expect(authDoctorPaletteItems(), isEmpty);

      shell.selectRequest(7);
      expect(authDoctorPaletteItems(), isEmpty);

      history.record(7, _response(200, message: 'OK'));
      expect(authDoctorPaletteItems(), isEmpty);

      history.record(7, _response(401, message: 'Unauthorized'));
      final items = authDoctorPaletteItems();
      expect(items.map((i) => i.title), ['401/403 Doctor: explain the last rejection']);
      expect(items.single.id, 'auth.doctor');
      expect(hasRejectionToExplain(7), isTrue);
      expect(hasRejectionToExplain(8), isFalse);
    });

    test('follows the open request, not another one', () {
      history.record(7, _response(403, message: 'Forbidden'));
      shell.selectRequest(8);

      expect(authDoctorPaletteItems(), isEmpty);

      shell.selectRequest(7);
      expect(authDoctorPaletteItems(), hasLength(1));
    });

    Future<void> pumpLauncher(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => ElevatedButton(onPressed: () => openAuthDoctor(context, requestId: 7), child: const Text('Go'))),
        ),
      ));
      await tester.tap(find.text('Go'));
      await tester.pump();
    }

    testWidgets('running it before any response says what to do first', (tester) async {
      await pumpLauncher(tester);

      expect(find.text('Send the request first: the doctor explains a real response.'), findsOneWidget);
    });

    testWidgets('running it on a response that worked says it was no rejection', (tester) async {
      history.record(7, _response(200, message: 'OK'));

      await pumpLauncher(tester);

      expect(find.text('The last response was 200 OK: it was not a rejection.'), findsOneWidget);
    });
  });
}
