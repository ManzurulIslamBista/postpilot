// The CLI runs a workspace file in the order the app shows it, and --folder / --request only pick from that order.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/cli/cli_main.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

BackupRequest _req(String name, {int? folder, int order = 0}) => BackupRequest(
  request: ApiRequestEntity(
    id: 0,
    collectionId: 0,
    folderId: folder,
    name: name,
    method: HttpMethod.get,
    url: 'https://api.test/${name.replaceAll(' ', '-')}',
    headers: const [],
    queryParams: const [],
    body: RequestBody.empty,
    auth: const RequestAuth(),
    orderIndex: order,
  ),
);

FolderEntity _folder(int id, String name, {int? parent, int order = 0}) =>
    FolderEntity(id: id, collectionId: 0, parentFolderId: parent, name: name, orderIndex: order);

/// Top level: Health(0), Auth(1){Login}, Orders(2){List(0), Admin(1){Purge}, Create(2)}, Logout(3).
/// The file lists folders first and requests in creation order, as an export of the app does.
BackupSnapshot _snapshot() => BackupSnapshot(
  exportedAt: DateTime.utc(2026),
  collections: [
    BackupCollection(
      name: 'API',
      folders: [
        _folder(1, 'Auth', order: 1),
        _folder(2, 'Orders', order: 2),
        _folder(3, 'Admin', parent: 2, order: 1),
      ],
      requests: [
        _req('Login', folder: 1),
        _req('Create', folder: 2, order: 2),
        _req('List', folder: 2),
        _req('Purge', folder: 3),
        _req('Logout', order: 3),
        _req('Health'),
      ],
    ),
  ],
);

const _expected = ['Health', 'Login', 'List', 'Purge', 'Create', 'Logout'];

(IOSink, StringBuffer) _capture() {
  final controller = StreamController<List<int>>();
  final buffer = StringBuffer();
  controller.stream.transform(utf8.decoder).listen(buffer.write);
  return (IOSink(controller.sink), buffer);
}

void main() {
  late Directory dir;
  late File workspace;
  late List<String> sent;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pp_cli_order');
    workspace = File(p.join(dir.path, 'workspace.json'))..writeAsStringSync(BackupCodec.encode(_snapshot()));
    sent = [];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<({int code, String out, String err})> cli(List<String> args) async {
    final (out, outBuffer) = _capture();
    final (err, errBuffer) = _capture();
    final code = await runCli(
      args,
      sender: (request) async {
        sent.add(Uri.parse(request.url).pathSegments.last);
        return const CliResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
      },
      out: out,
      err: err,
      environment: const {},
    );
    await out.flush();
    await err.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (code: code, out: outBuffer.toString(), err: errBuffer.toString());
  }

  List<String> namesIn(String json) => [
    for (final r in (jsonDecode(json) as Map<String, dynamic>)['requests'] as List<dynamic>) (r as Map)['name'] as String,
  ];

  test('runs folders and requests as the sidebar arranges them, not in file order', () async {
    final result = await cli(['run', workspace.path, '--report', 'json']);

    expect(result.code, 0, reason: result.err);
    expect(namesIn(result.out), _expected);
    expect(sent, _expected);
  });

  test('list shows the same order', () async {
    final result = await cli(['list', workspace.path]);

    final lines = result.out.trim().split('\n').skip(1).map((l) => l.trim().split(RegExp(r'\s+')).last).toList();
    expect(lines, _expected);
  });

  test('--request picks requests by name or by folder path and still runs them in the collection order', () async {
    final result = await cli(['run', workspace.path, '--report', 'json', '--request', 'Logout', '--request', 'Auth/Login']);

    expect(result.code, 0, reason: result.err);
    expect(namesIn(result.out), ['Login', 'Logout']);
  });

  test('--request together with --folder keeps what matches both', () async {
    final result = await cli(['run', workspace.path, '--report', 'json', '--folder', 'Orders', '--request', 'Create']);

    expect(namesIn(result.out), ['Create']);
  });

  test('--folder runs a folder and the ones under it in order', () async {
    final result = await cli(['run', workspace.path, '--report', 'json', '--folder', 'Orders']);

    expect(namesIn(result.out), ['List', 'Purge', 'Create']);
  });

  test('a --request that matches nothing stops the run before anything is sent, exit code 2, and says what to use', () async {
    final result = await cli(['run', workspace.path, '--request', 'Login', '--request', 'Orders/Nope']);

    expect(result.code, 2);
    expect(result.err, contains('No request matches "Orders/Nope"'));
    expect(result.err, contains('postpilot list'));
    expect(sent, isEmpty);
  });

  test('--request needs a value', () async {
    final result = await cli(['run', workspace.path, '--request']);

    expect(result.code, 2);
    expect(result.err, contains('--request needs a value'));
  });

  test('a file from before order was written lists folders first, then requests, each in file order', () async {
    final json = jsonDecode(workspace.readAsStringSync()) as Map<String, dynamic>;
    void strip(Object? node) {
      if (node is Map<String, dynamic>) {
        node.remove('order');
        node.values.forEach(strip);
      } else if (node is List) {
        node.forEach(strip);
      }
    }

    strip(json);
    workspace.writeAsStringSync(jsonEncode(json));

    final result = await cli(['run', workspace.path, '--report', 'json']);

    // top: folders Auth, Orders (file order) then requests Logout, Health (file order); Orders: Admin first, then
    // Create, List (file order)
    expect(namesIn(result.out), ['Login', 'Purge', 'Create', 'List', 'Logout', 'Health']);
  });

  test('the file an app writes carries order, and reading it back gives the same order', () {
    final text = BackupCodec.encode(_snapshot());
    final decoded = BackupCodec.decode(text).collections.single;

    expect(decoded.folders.map((f) => (f.name, f.orderIndex)), [('Auth', 1), ('Orders', 2), ('Admin', 1)]);
    expect(decoded.requests.map((r) => (r.request.name, r.request.orderIndex)), [
      ('Login', 0),
      ('Create', 2),
      ('List', 0),
      ('Purge', 0),
      ('Logout', 3),
      ('Health', 0),
    ]);
    final raw = jsonDecode(text) as Map<String, dynamic>;
    expect(((raw['collections'] as List).single as Map)['folders'], everyElement(containsPair('order', isA<int>())));
  });
}
