// "Save as example" attaches a response to a saved request, so it is offered
// everywhere except where the response belongs to none: the team request form.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/auth/domain/entities/app_user_entity.dart';
import 'package:postpilot/features/auth/domain/repositories/auth_repository.dart';
import 'package:postpilot/features/auth/presentation/view_models/auth_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/response_examples_view_model.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/response_viewer.dart';
import 'package:postpilot/features/team/domain/entities/cloud_request_entity.dart';
import 'package:postpilot/features/team/domain/repositories/team_repository.dart';
import 'package:postpilot/features/team/presentation/view_models/team_view_model.dart';
import 'package:postpilot/features/team/presentation/widgets/request_form_dialog.dart';
import 'package:provider/provider.dart';

final class _NoExamples implements ResponseExampleRepository {
  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class _SignedIn implements AuthRepository {
  @override
  AppUserEntity? get currentUser => const AppUserEntity(id: 'u1', email: 'a@b.c');

  @override
  Stream<AppUserEntity?> get authStateChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class _UnusedTeamRepository implements TeamRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

ApiResponseEntity _response() => ApiResponseEntity(
      statusCode: 200,
      statusMessage: 'OK',
      headers: const {'content-type': 'application/json'},
      bodyBytes: Uint8List.fromList('{"ok":true}'.codeUnits),
      duration: const Duration(milliseconds: 12),
    );

void main() {
  setUp(() async {
    await locator.reset();
    locator.registerFactory<ResponseExamplesViewModel>(() => ResponseExamplesViewModel(_NoExamples()));
  });

  tearDown(() => locator.reset());

  Future<void> pumpViewer(WidgetTester tester, {bool canSaveExamples = true}) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ResponseViewer(response: _response(), requestId: 1, canSaveExamples: canSaveExamples),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the response viewer offers Save as example by default', (tester) async {
    await pumpViewer(tester);

    expect(find.byTooltip('Save as example'), findsOneWidget);
  });

  testWidgets('and hides it, keeping copy and download, when told examples cannot be saved', (tester) async {
    await pumpViewer(tester, canSaveExamples: false);

    expect(find.byTooltip('Save as example'), findsNothing);
    expect(find.byTooltip('Copy body'), findsOneWidget);
    expect(find.byTooltip('Download body'), findsOneWidget);
  });

  testWidgets('the response under a team request has no Save as example', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthViewModel(_SignedIn());
    final team = TeamViewModel(_UnusedTeamRepository(), sendRequest: (request, {cancelToken}) async => _response());
    addTearDown(auth.dispose);
    addTearDown(team.dispose);
    final request = CloudRequestEntity(
      id: 1,
      collectionId: 3,
      folderId: null,
      name: 'Users',
      method: 'GET',
      url: 'https://api.example.com/users',
      headers: const [],
      body: '',
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewModel>.value(value: auth),
        ChangeNotifierProvider<TeamViewModel>.value(value: team),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => RequestFormDialog.show(context, request: request, canEdit: false),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('200 OK'), findsOneWidget);
    expect(find.byTooltip('Copy body'), findsOneWidget);
    expect(find.byTooltip('Save as example'), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });
}
