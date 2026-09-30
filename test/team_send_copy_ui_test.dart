import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/auth/domain/entities/app_user_entity.dart';
import 'package:postpilot/features/auth/domain/repositories/auth_repository.dart';
import 'package:postpilot/features/auth/presentation/view_models/auth_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/response_examples_view_model.dart';
import 'package:postpilot/features/team/domain/entities/cloud_collection_entity.dart';
import 'package:postpilot/features/team/domain/entities/cloud_folder_entity.dart';
import 'package:postpilot/features/team/domain/entities/cloud_request_entity.dart';
import 'package:postpilot/features/team/domain/entities/collection_invite_entity.dart';
import 'package:postpilot/features/team/domain/entities/collection_member_entity.dart';
import 'package:postpilot/features/team/domain/entities/member_role.dart';
import 'package:postpilot/features/team/domain/repositories/team_repository.dart';
import 'package:postpilot/features/team/domain/usecases/copy_cloud_collection_usecase.dart';
import 'package:postpilot/features/team/presentation/view_models/team_view_model.dart';
import 'package:postpilot/features/team/presentation/widgets/collection_detail_panel.dart';
import 'package:postpilot/features/team/presentation/widgets/request_form_dialog.dart';
import 'package:provider/provider.dart';

const _user = AppUserEntity(id: 'u1', email: 'a@b.c');

final class _SignedInAuth implements AuthRepository {
  @override
  AppUserEntity? get currentUser => _user;

  @override
  Stream<AppUserEntity?> get authStateChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// The response viewer lists saved examples of a request; a cloud request has none.
final class _NoExamples implements ResponseExampleRepository {
  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class _TeamRepository implements TeamRepository {
  final members = StreamController<List<CollectionMemberEntity>>.broadcast();
  final folders = StreamController<List<CloudFolderEntity>>.broadcast();
  final requests = StreamController<List<CloudRequestEntity>>.broadcast();

  @override
  Stream<List<CollectionMemberEntity>> watchMembers(int collectionId) => members.stream;

  @override
  Stream<List<CloudFolderEntity>> watchFolders(int collectionId) => folders.stream;

  @override
  Stream<List<CloudRequestEntity>> watchRequests(int collectionId) => requests.stream;

  @override
  Future<List<CollectionInviteEntity>> listCollectionInvites(int collectionId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class _Copier implements UseCase<CopiedCollection, CopyCloudCollectionParams> {
  final calls = <CopyCloudCollectionParams>[];

  @override
  Future<CopiedCollection> call(CopyCloudCollectionParams params) async {
    calls.add(params);
    return const CopiedCollection(collectionId: 9, folders: 1, requests: 2);
  }
}

CloudRequestEntity _cloud({String url = 'https://api.example.com/users'}) => CloudRequestEntity(
      id: 1,
      collectionId: 3,
      folderId: null,
      name: 'Users',
      method: 'GET',
      url: url,
      headers: const [],
      body: '',
      updatedAt: DateTime(2026),
    );

ApiResponseEntity _response() => ApiResponseEntity(
      statusCode: 200,
      statusMessage: 'OK',
      headers: const {'content-type': 'application/json'},
      bodyBytes: Uint8List.fromList('{"ok":true}'.codeUnits),
      duration: const Duration(milliseconds: 12),
    );

void main() {
  late _TeamRepository repository;
  late TeamViewModel vm;

  setUp(() async {
    await locator.reset();
    locator.registerFactory<ResponseExamplesViewModel>(() => ResponseExamplesViewModel(_NoExamples()));
    repository = _TeamRepository();
  });

  tearDown(() => vm.dispose());

  Future<void> openRequestForm(WidgetTester tester, CloudRequestEntity request, {required bool canEdit}) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewModel>(create: (_) => AuthViewModel(_SignedInAuth())),
        ChangeNotifierProvider<TeamViewModel>.value(value: vm),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => RequestFormDialog.show(context, request: request, canEdit: canEdit),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('RequestFormDialog: Send', () {
    testWidgets('shows progress, then status, time and body of the response, then a friendly error', (tester) async {
      var fail = false;
      final release = Completer<void>();
      final sent = <Object>[];
      vm = TeamViewModel(repository, sendRequest: (request, {cancelToken}) async {
        sent.add(request);
        await release.future;
        if (fail) throw const InvalidUrlException('bad');
        return _response();
      });
      vm.selectCollection(3);
      repository.members.add(const [CollectionMemberEntity(collectionId: 3, userId: 'u1', role: MemberRole.owner)]);
      await tester.pump();
      await openRequestForm(tester, _cloud(), canEdit: true);

      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Sending…'), findsNothing);

      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(find.text('Sending…'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      release.complete();
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(find.text('200 OK'), findsOneWidget);
      expect(find.text('12 ms'), findsOneWidget);
      expect(find.text('Headers'), findsWidgets);

      fail = true;
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.textContaining('needs a host'), findsOneWidget);
      expect(find.text('200 OK'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('a viewer, who cannot edit, can still send; Send is disabled while there is no URL', (tester) async {
      vm = TeamViewModel(repository, sendRequest: (request, {cancelToken}) async => _response());

      await openRequestForm(tester, _cloud(url: ''), canEdit: false);

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('the Send button typed into becomes enabled as soon as there is a URL', (tester) async {
      vm = TeamViewModel(repository, sendRequest: (request, {cancelToken}) async => _response());
      vm.selectCollection(3);
      repository.members.add(const [CollectionMemberEntity(collectionId: 3, userId: 'u1', role: MemberRole.editor)]);
      await tester.pump();
      await openRequestForm(tester, _cloud(url: ''), canEdit: true);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNull);

      await tester.enterText(find.byType(TextField).at(1), 'https://a.test/x');
      await tester.pump();

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNotNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('without a send function there is no Send button', (tester) async {
      vm = TeamViewModel(repository);

      await openRequestForm(tester, _cloud(), canEdit: true);

      expect(find.text('Send'), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });
  });

  group('CollectionDetailPanel: Copy to my collections', () {
    testWidgets('copies the loaded collection for any member and reports the count', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final copier = _Copier();
      vm = TeamViewModel(repository, copyCollection: copier);
      vm.selectCollection(3);
      repository.members.add(const [CollectionMemberEntity(collectionId: 3, userId: 'u1', role: MemberRole.viewer)]);
      repository.folders.add(const [CloudFolderEntity(id: 10, collectionId: 3, parentFolderId: null, name: 'Users')]);
      repository.requests.add([_cloud()]);
      await tester.pump();
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<TeamViewModel>.value(value: vm)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CollectionDetailPanel(
              collection: const CloudCollectionEntity(id: 3, name: 'Team API', ownerId: 'someone-else'),
              currentUser: _user,
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byTooltip('Copy to my collections'));
      await tester.pumpAndSettle();

      expect(find.text('Copied "Team API" to your collections (1 folder, 2 requests)'), findsOneWidget);
      expect(copier.calls.single.name, 'Team API');
      expect(copier.calls.single.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the button waits until the collection has loaded, and is hidden without a copy use case', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      vm = TeamViewModel(repository, copyCollection: _Copier());
      vm.selectCollection(3);
      Widget panel() => MultiProvider(
            providers: [ChangeNotifierProvider<TeamViewModel>.value(value: vm)],
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: CollectionDetailPanel(
                  collection: const CloudCollectionEntity(id: 3, name: 'Team API', ownerId: 'someone-else'),
                  currentUser: _user,
                ),
              ),
            ),
          );

      await tester.pumpWidget(panel());
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.copy_all_outlined)).onPressed, isNull);

      vm.dispose();
      vm = TeamViewModel(repository);
      await tester.pumpWidget(panel());
      expect(find.byTooltip('Copy to my collections'), findsNothing);
    });
  });
}
