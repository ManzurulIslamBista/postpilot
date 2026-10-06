// The "Max upload size" setting, from its JSON to the client, and the use cases that carry an upload.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/network/upload_body.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/code_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/effective_request_options.dart';
import 'package:postpilot/features/settings/presentation/view_models/settings_view_model.dart';
import 'package:postpilot/features/settings/presentation/widgets/general_settings_pane.dart';
import 'package:postpilot/features/settings/presentation/widgets/setting_row.dart';
import '../settings/fakes/fake_settings_repositories.dart';

KeyValueItem _file(String key, String path, {String contentType = ''}) =>
    KeyValueItem(key: key, value: path, kind: FormFieldKind.file, contentType: contentType);

ApiRequestEntity _request(RequestBody body, {HttpMethod method = HttpMethod.post}) => ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: 'upload',
      method: method,
      url: 'https://files.example.com/upload',
      headers: const [],
      queryParams: const [],
      body: body,
      auth: const RequestAuth(type: AuthType.none),
    );

void main() {
  group('AppSettings.maxUploadSizeMb', () {
    test('is 100 MB unless set, and an older settings document without it gets the default', () {
      expect(const AppSettings().maxUploadSizeMb, 100);
      expect(AppSettings.fromJson(const {'maxResponseSizeMb': 7}).maxUploadSizeMb, 100);
      expect(AppSettings.decode(null).maxUploadSizeMb, 100);
    });

    test('is read from JSON, kept within 0..10240, and a damaged value falls back to the default', () {
      expect(AppSettings.fromJson(const {'maxUploadSizeMb': 25}).maxUploadSizeMb, 25);
      expect(AppSettings.fromJson(const {'maxUploadSizeMb': 0}).maxUploadSizeMb, 0);
      expect(AppSettings.fromJson(const {'maxUploadSizeMb': -3}).maxUploadSizeMb, 100, reason: 'a negative size must not turn into "unlimited"');
      expect(AppSettings.fromJson(const {'maxUploadSizeMb': 'big'}).maxUploadSizeMb, 100);
      expect(AppSettings.fromJson(const {'maxUploadSizeMb': 99999999}).maxUploadSizeMb, anyOf(100, AppSettings.maxUploadSizeMbLimit));
    });

    test('survives a JSON round trip and takes part in equality', () {
      const settings = AppSettings(maxUploadSizeMb: 12);

      expect(AppSettings.fromJson(settings.toJson()), settings);
      expect(settings.toJson()['maxUploadSizeMb'], 12);
      expect(settings.copyWith(maxUploadSizeMb: 13), isNot(settings));
      expect(settings.copyWith(maxUploadSizeMb: 12).hashCode, settings.hashCode);
    });

    test('becomes the byte limit of a send; 0 is no limit', () {
      expect(EffectiveRequestOptions.resolve(const AppSettings(maxUploadSizeMb: 2), null).maxUploadBytes, 2 * 1024 * 1024);
      expect(EffectiveRequestOptions.resolve(const AppSettings(maxUploadSizeMb: 0), null).maxUploadBytes, isNull);
      expect(EffectiveRequestOptions.resolve(const AppSettings(maxUploadSizeMb: 2), null).toApiOptions().maxUploadBytes, 2 * 1024 * 1024);
      expect(const ApiRequestOptions().maxUploadBytes, isNull, reason: 'a client used without settings has no limit of its own');
    });
  });

  group('the settings screen', () {
    testWidgets('the view model holds the size within its range', (tester) async {
      final viewModel = SettingsViewModel(FakeSettingsRepository());

      viewModel.setMaxUploadSizeMb(-1);
      expect(viewModel.settings.maxUploadSizeMb, 0);
      viewModel.setMaxUploadSizeMb(99999999);
      expect(viewModel.settings.maxUploadSizeMb, AppSettings.maxUploadSizeMbLimit);
      viewModel.setMaxUploadSizeMb(40);
      expect(viewModel.settings.maxUploadSizeMb, 40);

      viewModel.dispose();
    });

    for (final brightness in Brightness.values) {
      for (final width in [1200.0, 420.0]) {
        testWidgets('General shows "Max upload size" and edits it, ${brightness.name} at ${width.toInt()} px', (tester) async {
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final viewModel = SettingsViewModel(FakeSettingsRepository());
          await tester.pumpWidget(
            MaterialApp(
              theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ListenableBuilder(
                    listenable: viewModel,
                    builder: (context, _) => GeneralSettingsPane(viewModel: viewModel, isWeb: false),
                  ),
                ),
              ),
            ),
          );

          expect(find.text('Max upload size'), findsOneWidget);
          expect(find.textContaining('refused before it is sent'), findsOneWidget);
          final field = find.descendant(
            of: find.ancestor(of: find.text('Max upload size'), matching: find.byType(SettingRow)),
            matching: find.byType(TextField),
          );
          expect(tester.widget<TextField>(field).controller!.text, '100');

          await tester.enterText(field, '8');
          await tester.pump();

          expect(viewModel.settings.maxUploadSizeMb, 8);
          expect(tester.takeException(), isNull);
          // The save delay is a real timer: let it run out before the test ends.
          await tester.pump(const Duration(seconds: 1));
          viewModel.dispose();
        });
      }
    }
  });

  group('the use cases carry an upload', () {
    late _RecordingClient client;
    late FakeSettingsRepository settings;

    BuildVariableResolverUseCase resolver() =>
        BuildVariableResolverUseCase(_NoCollectionVariables(), _Environment(const {'uploadDir': '/srv/up'}), _NoGlobals());

    SendRequestUseCase sender() => SendRequestUseCase(client, resolver(), _NoHistory(), _NoCollectionAuth(), settings);

    setUp(() {
      client = _RecordingClient();
      settings = FakeSettingsRepository();
    });

    test('the client gets the plan, not bytes, with the {{variable}} path resolved and the limit from the settings', () async {
      settings.changeElsewhere(const AppSettings(maxUploadSizeMb: 3));
      final request = _request(RequestBody(type: BodyType.formData, formFields: [
        KeyValueItem(key: 'title', value: 'Cat'),
        _file('photo', '{{uploadDir}}/cat.png'),
      ]));

      await sender()(request);

      final sent = client.sent.single;
      expect(sent.body, isA<MultipartUpload>());
      final parts = (sent.body! as MultipartUpload).parts;
      expect((parts[1] as UploadFilePart).file.path, '/srv/up/cat.png');
      expect(sent.options.maxUploadBytes, 3 * 1024 * 1024);
      expect(sent.headers['Content-Type'], 'multipart/form-data; boundary=${(sent.body! as MultipartUpload).boundary}');
    });

    test('a binary body reaches the client as a plan too', () async {
      await sender()(_request(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '{{uploadDir}}/a.tar')), method: HttpMethod.put));

      final body = client.sent.single.body;
      expect(body, isA<BinaryUpload>());
      expect((body! as BinaryUpload).file.path, '/srv/up/a.tar');
      expect(client.sent.single.headers['Content-Type'], 'application/octet-stream');
    });

    test('an undefined variable in a file path stops the send like any other undefined variable', () async {
      final request = _request(RequestBody(type: BodyType.formData, formFields: [_file('photo', '{{nowhere}}/cat.png')]));

      await expectLater(sender()(request), throwsA(predicate((e) => '$e'.contains('{{nowhere}}') && '$e'.contains('the form field "photo"'))));
      expect(client.sent, isEmpty);
    });

    test('a snippet is built from the same plan the client was given', () async {
      final request = _request(RequestBody(type: BodyType.formData, formFields: [
        KeyValueItem(key: 'title', value: 'Cat'),
        _file('photo', '{{uploadDir}}/cat.png', contentType: 'image/png'),
      ]));
      final generator = _CapturingGenerator();

      await sender()(request);
      await GenerateCodeSnippetUseCase(resolver(), _NoCollectionAuth(), settings: settings)(GenerateCodeSnippetParams(request, generator));

      List<String> shape(UploadBody body) => [
            for (final part in (body as MultipartUpload).parts)
              switch (part) {
                UploadTextPart(:final name, :final value) => 'text $name=$value',
                UploadFilePart(:final name, :final file) => 'file $name=${file.path} ${file.fileName} ${file.contentType}',
              },
          ];
      expect(shape(generator.spec!.upload!), shape(client.sent.single.body! as UploadBody));
      expect(generator.spec!.bodyBytes, isNull);
      expect(client.sent.single.body, isNot(isA<List<int>>()));
    });
  });
}

final class _RecordingClient implements ApiClient {
  final sent = <ApiRequestSpec>[];

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add(spec);
    return const ApiHttpResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
  }
}

final class _CapturingGenerator implements CodeGenerator {
  ResolvedRequestSpec? spec;

  @override
  String get id => 'capture';
  @override
  String get label => 'capture';
  @override
  String generate(ResolvedRequestSpec spec) {
    this.spec = spec;
    return '';
  }
}

final class _NoHistory implements HistoryRepository {
  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoCollectionAuth implements CollectionAuthRepository {
  @override
  Future<String?> getAuthJson(int collectionId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoCollectionVariables implements CollectionVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap(int collectionId) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Environment implements EnvironmentRepository {
  final Map<String, String> variables;
  _Environment(this.variables);

  @override
  Future<Map<String, String>> getActiveVariables() async => variables;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoGlobals implements GlobalVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
