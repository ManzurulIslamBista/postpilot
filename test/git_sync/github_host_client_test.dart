import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/data/github/github_host_client.dart';
import 'package:postpilot/features/git_sync/data/secure_git_credentials_store.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_credentials_store.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_host_client.dart';

const repo = RepoRef(provider: GitProvider.github, owner: 'octo', repo: 'hello');
const base = '/repos/octo/hello';

/// Access-Control-Allow-Headers answered by api.github.com to a browser
/// preflight, plus the CORS-safelisted names browsers never list.
const _corsAllowed = <String>{
  'authorization',
  'content-type',
  'if-match',
  'if-modified-since',
  'if-none-match',
  'if-unmodified-since',
  'accept-encoding',
  'x-github-otp',
  'x-requested-with',
  'user-agent',
  'graphql-features',
  'x-github-next-global-id',
  'x-github-api-version',
  'x-fetch-nonce',
  'copilot-integration-id',
  'dd-client-token',
  'x-client-application',
  'accept',
  'accept-language',
  'content-language',
};

const _sentByClient = <String>{'authorization', 'accept', 'x-github-api-version', 'content-type'};

class _Call {
  _Call(this.method, this.uri, this.headers, this.raw) : body = raw == null ? null : jsonDecode(raw);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? raw;
  final Object? body;

  String get path => uri.path;
  String get label => '$method $path';
  Map<String, String> get query => uri.queryParameters;
}

class _Route {
  _Route(this.method, this.path, this.query, this.status, this.text, this.headers, this.fail);

  final String method;
  final String path;
  final Map<String, String> query;
  final int status;
  final String text;
  final Map<String, String> headers;
  final DioExceptionType? fail;
}

class _FakeGitHub implements HttpClientAdapter {
  final calls = <_Call>[];
  final unstubbed = <String>[];
  final _routes = <_Route>[];

  List<String> get labels => [for (final c in calls) c.label];

  void on(
    String method,
    String path, {
    Map<String, String> query = const {},
    int status = 200,
    Object? json,
    String? raw,
    Map<String, String> headers = const {},
    DioExceptionType? fail,
  }) {
    final text = raw ?? (json == null ? '' : jsonEncode(json));
    _routes.add(_Route(method, path, query, status, text, headers, fail));
  }

  _Route? _match(_Call call) {
    _Route? best;
    for (final r in _routes) {
      final matches = r.method == call.method &&
          r.path == call.path &&
          r.query.entries.every((q) => call.query[q.key] == q.value);
      if (matches && (best == null || r.query.length >= best.query.length)) best = r;
    }
    return best;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    String? raw;
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      raw = utf8.decode(bytes);
    }
    final headers = {
      // Dio's browser adapter strips Content-Length, so it never reaches a preflight.
      for (final e in options.headers.entries)
        if (e.key.toLowerCase() != 'content-length') e.key.toLowerCase(): '${e.value}',
    };
    final call = _Call(options.method, options.uri, headers, raw);
    calls.add(call);
    final route = _match(call);
    if (route == null) {
      unstubbed.add(call.label);
      return ResponseBody.fromString(jsonEncode({'message': 'unstubbed ${call.label}'}), 500);
    }
    final fail = route.fail;
    if (fail != null) throw DioException(requestOptions: options, type: fail);
    return ResponseBody.fromString(
      route.text,
      route.status,
      headers: {
        'content-type': ['application/json; charset=utf-8'],
        for (final e in route.headers.entries) e.key: [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Creds implements GitCredentialsStore {
  _Creds(this.token);

  String? token;

  @override
  Future<String?> readToken(GitProvider provider) async => token;

  @override
  Future<void> saveToken(GitProvider provider, String token) async => this.token = token;

  @override
  Future<void> deleteToken(GitProvider provider) async => token = null;
}

class _BrokenStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('WebCrypto is not available');
}

Matcher throwsGit<T extends GitHostException>([Matcher? message]) =>
    throwsA(isA<T>().having((e) => e.message, 'message', message ?? anything));

Matcher throwsPlainGit([Matcher? message]) => throwsA(
      isA<GitHostException>()
          .having((e) => e.runtimeType, 'runtimeType', GitHostException)
          .having((e) => e.message, 'message', message ?? anything),
    );

Map<String, dynamic> repoJson({int size = 12, bool? push = true, bool private = false, String branch = 'main'}) => {
      'default_branch': branch,
      'private': private,
      'size': size,
      if (push != null) 'permissions': {'admin': false, 'push': push, 'pull': true},
    };

void main() {
  late _FakeGitHub gh;
  late _Creds creds;
  late GitHubHostClient client;

  setUp(() {
    gh = _FakeGitHub();
    creds = _Creds('ghp_secret');
    client = GitHubHostClient(creds, dio: Dio()..httpClientAdapter = gh);
  });

  tearDown(() {
    expect(gh.unstubbed, isEmpty, reason: 'requests without a canned response');
    for (final c in gh.calls) {
      expect(c.uri.origin, 'https://api.github.com');
      expect(c.headers.keys.toSet().difference(_corsAllowed), isEmpty, reason: '${c.label} sends a header GitHub blocks cross-origin');
    }
  });

  group('requests', () {
    test('send the token, Accept and API version; GETs have no Content-Type', () async {
      gh.on('GET', '/user', json: {'login': 'octo'});
      expect(await client.getAuthenticatedLogin(), 'octo');
      final h = gh.calls.single.headers;
      expect(h['authorization'], 'Bearer ghp_secret');
      expect(h['accept'], 'application/vnd.github+json');
      expect(h['x-github-api-version'], '2022-11-28');
      expect(h.containsKey('content-type'), isFalse);
    });

    test('public reads work without a token and send no Authorization header', () async {
      creds.token = null;
      gh.on('GET', base, json: repoJson(push: null));
      await client.getRepo(repo);
      expect(gh.calls.single.headers.containsKey('authorization'), isFalse);
    });

    test('a blank token counts as no token', () async {
      creds.token = '   ';
      gh.on('GET', base, json: repoJson(push: null));
      await client.getRepo(repo);
      expect(gh.calls.single.headers.containsKey('authorization'), isFalse);
    });

    test('bodies are JSON', () async {
      gh.on('POST', '$base/git/refs', status: 201, json: {});
      await client.createBranch(repo, 'dev', fromSha: 'abc');
      expect(gh.calls.single.headers['content-type'], startsWith('application/json'));
    });

    test('answers that can change bypass the browser cache, sha-addressed ones do not', () async {
      gh.on('GET', '$base/git/ref/heads/main', json: {'object': {'sha': 'a'}});
      gh.on('GET', '$base/git/blobs/b1', json: {'content': 'x', 'encoding': 'utf-8'});
      await client.getBranchHead(repo, 'main');
      await client.getBlobText(repo, 'b1');
      expect(gh.calls[0].query['cb'], isNotNull);
      expect(gh.calls[1].query.containsKey('cb'), isFalse);
    });

    test('every endpoint, writes included, sends only headers GitHub allows cross-origin', () async {
      gh.on('GET', '/user', json: {'login': 'octo'});
      gh.on('GET', base, json: repoJson());
      gh.on('POST', '/user/repos', status: 201, json: {'name': 'n', 'owner': {'login': 'octo'}});
      gh.on('GET', '$base/branches', json: [{'name': 'main'}]);
      gh.on('GET', '$base/git/ref/heads/main', json: {'object': {'sha': 'p1'}});
      gh.on('POST', '$base/git/refs', status: 201, json: {});
      gh.on('GET', '$base/git/commits/p1', json: {'tree': {'sha': 't1'}});
      gh.on('GET', '$base/git/trees/t1', json: {'tree': [], 'truncated': false});
      gh.on('GET', '$base/git/blobs/b1', json: {'content': 'eA==', 'encoding': 'base64'});
      gh.on('POST', '$base/git/trees', status: 201, json: {'sha': 't2'});
      gh.on('POST', '$base/git/commits', status: 201, json: {'sha': 'c2'});
      gh.on('PATCH', '$base/git/refs/heads/main', json: {});
      gh.on('GET', '$base/commits', json: []);
      gh.on('GET', '$base/contributors', json: []);

      await client.getAuthenticatedLogin();
      await client.getRepo(repo);
      await client.createRepo(provider: GitProvider.github, name: 'n', private: false);
      await client.listBranches(repo);
      await client.getBranchHead(repo, 'main');
      await client.createBranch(repo, 'dev', fromSha: 'p1');
      await client.getTree(repo, 'p1');
      await client.getBlobText(repo, 'b1');
      await client.commit(repo, branch: 'main', parentSha: 'p1', message: 'm', changes: {'a': 'b'});
      await client.listCommits(repo, branch: 'main');
      await client.listContributors(repo);

      final sent = {for (final c in gh.calls) ...c.headers.keys};
      expect(sent.difference(_sentByClient), isEmpty);
    });
  });

  group('getAuthenticatedLogin', () {
    test('needs a token and does not call GitHub without one', () async {
      creds.token = null;
      await expectLater(client.getAuthenticatedLogin(), throwsGit<GitAuthException>(equals('No GitHub token saved')));
      expect(gh.calls, isEmpty);
    });

    test('401 means the token was rejected', () async {
      gh.on('GET', '/user', status: 401, json: {'message': 'Bad credentials'});
      await expectLater(client.getAuthenticatedLogin(), throwsGit<GitAuthException>());
    });
  });

  group('getRepo', () {
    test('maps the facts and skips the branch probe when the repository has content', () async {
      gh.on('GET', base, json: repoJson(size: 5, push: true, private: true, branch: 'trunk'));
      final info = await client.getRepo(repo);
      expect(info.defaultBranch, 'trunk');
      expect(info.canPush, isTrue);
      expect(info.isPrivate, isTrue);
      expect(info.isEmpty, isFalse);
      expect(gh.calls, hasLength(1));
    });

    test('permissions.push false means read-only', () async {
      gh.on('GET', base, json: repoJson(push: false));
      expect((await client.getRepo(repo)).canPush, isFalse);
    });

    test('missing permissions (anonymous read) means no push', () async {
      gh.on('GET', base, json: repoJson(push: null));
      expect((await client.getRepo(repo)).canPush, isFalse);
    });

    for (final (name, status, json) in <(String, int, Object?)>[
      ('200 with an empty list', 200, <Object>[]),
      ('404', 404, {'message': 'Not Found'}),
      ('409', 409, {'message': 'Git Repository is empty.'}),
    ]) {
      test('size 0 and a branch probe answering $name is an empty repository', () async {
        gh.on('GET', base, json: repoJson(size: 0));
        gh.on('GET', '$base/branches', status: status, json: json);
        expect((await client.getRepo(repo)).isEmpty, isTrue);
        expect(gh.calls.last.query['per_page'], '1');
      });
    }

    test('size 0 but with a branch is not empty', () async {
      gh.on('GET', base, json: repoJson(size: 0));
      gh.on('GET', '$base/branches', json: [{'name': 'main'}]);
      expect((await client.getRepo(repo)).isEmpty, isFalse);
    });

    test('404 says the repository is missing or invisible', () async {
      gh.on('GET', base, status: 404, json: {'message': 'Not Found'});
      await expectLater(
        client.getRepo(repo),
        throwsGit<GitNotFoundException>(equals('Repository octo/hello not found, or your token cannot see it')),
      );
    });
  });

  group('createRepo', () {
    test('creates an initialised repository and returns the reference GitHub reports', () async {
      gh.on('POST', '/user/repos', status: 201, json: {'name': 'notes', 'owner': {'login': 'octo'}});
      final ref = await client.createRepo(provider: GitProvider.github, name: 'notes', private: true, description: 'API collections');
      expect(ref, const RepoRef(provider: GitProvider.github, owner: 'octo', repo: 'notes'));
      expect(gh.calls.single.body, {'name': 'notes', 'private': true, 'description': 'API collections', 'auto_init': true});
    });

    test('leaves the description out when there is none', () async {
      gh.on('POST', '/user/repos', status: 201, json: {'name': 'notes', 'owner': {'login': 'octo'}});
      await client.createRepo(provider: GitProvider.github, name: 'notes', private: false);
      expect(gh.calls.single.body, {'name': 'notes', 'private': false, 'auto_init': true});
    });

    test('needs a token and does not call GitHub without one', () async {
      creds.token = null;
      await expectLater(
        client.createRepo(provider: GitProvider.github, name: 'notes', private: false),
        throwsGit<GitAuthException>(equals('No GitHub token saved')),
      );
      expect(gh.calls, isEmpty);
    });

    test('a taken name comes back with GitHub\'s reason', () async {
      gh.on('POST', '/user/repos', status: 422, json: {
        'message': 'Repository creation failed.',
        'errors': [
          {'resource': 'Repository', 'code': 'custom', 'field': 'name', 'message': 'name already exists on this account'},
        ],
      });
      await expectLater(
        client.createRepo(provider: GitProvider.github, name: 'notes', private: false),
        throwsPlainGit(allOf(contains('Repository creation failed.'), contains('name already exists on this account'))),
      );
    });
  });

  group('listBranches', () {
    test('follows pages of 100 until a short page', () async {
      gh.on('GET', '$base/branches', query: {'page': '1'}, json: [for (var i = 0; i < 100; i++) {'name': 'b$i'}]);
      gh.on('GET', '$base/branches', query: {'page': '2'}, json: [{'name': 'x'}, {'name': 'y'}]);
      final names = await client.listBranches(repo);
      expect(names, hasLength(102));
      expect(names.first, 'b0');
      expect(names.last, 'y');
      expect(gh.calls.map((c) => c.query['page']), ['1', '2']);
      expect(gh.calls.every((c) => c.query['per_page'] == '100'), isTrue);
    });

    test('a short first page is a single request', () async {
      gh.on('GET', '$base/branches', json: [{'name': 'main'}, {'name': 'dev'}]);
      expect(await client.listBranches(repo), ['main', 'dev']);
      expect(gh.calls, hasLength(1));
    });

    test('exactly 100 branches asks for one more page', () async {
      gh.on('GET', '$base/branches', query: {'page': '1'}, json: [for (var i = 0; i < 100; i++) {'name': 'b$i'}]);
      gh.on('GET', '$base/branches', query: {'page': '2'}, json: []);
      expect(await client.listBranches(repo), hasLength(100));
      expect(gh.calls, hasLength(2));
    });

    test('an empty repository has no branches', () async {
      gh.on('GET', '$base/branches', status: 409, json: {'message': 'Git Repository is empty.'});
      expect(await client.listBranches(repo), isEmpty);
    });

    test('an unknown repository is not found', () async {
      gh.on('GET', '$base/branches', status: 404, json: {'message': 'Not Found'});
      await expectLater(client.listBranches(repo), throwsGit<GitNotFoundException>());
    });
  });

  group('getBranchHead', () {
    test('returns the head sha', () async {
      gh.on('GET', '$base/git/ref/heads/main', json: {'ref': 'refs/heads/main', 'object': {'sha': 'abc123', 'type': 'commit'}});
      expect(await client.getBranchHead(repo, 'main'), 'abc123');
    });

    test('a missing branch is null', () async {
      gh.on('GET', '$base/git/ref/heads/nope', status: 404, json: {'message': 'Not Found'});
      expect(await client.getBranchHead(repo, 'nope'), isNull);
    });

    test('an empty repository is null', () async {
      gh.on('GET', '$base/git/ref/heads/main', status: 409, json: {'message': 'Git Repository is empty.'});
      expect(await client.getBranchHead(repo, 'main'), isNull);
    });

    test('slashes in the branch name stay path separators, other characters are encoded per segment', () async {
      gh.on('GET', '$base/git/ref/heads/feature/login%20v2', json: {'object': {'sha': 'abc'}});
      expect(await client.getBranchHead(repo, 'feature/login v2'), 'abc');
      expect(gh.calls.single.path, '$base/git/ref/heads/feature/login%20v2');
    });

    test('other failures are not swallowed', () async {
      gh.on('GET', '$base/git/ref/heads/main', status: 500, json: {'message': 'Server Error'});
      await expectLater(client.getBranchHead(repo, 'main'), throwsPlainGit(equals('Server Error')));
    });
  });

  group('createBranch', () {
    test('posts the full ref name and the source sha', () async {
      gh.on('POST', '$base/git/refs', status: 201, json: {});
      await client.createBranch(repo, 'feature/x', fromSha: 'abc');
      expect(gh.calls.single.body, {'ref': 'refs/heads/feature/x', 'sha': 'abc'});
    });

    test('needs a token and does not call GitHub without one', () async {
      creds.token = null;
      await expectLater(client.createBranch(repo, 'dev', fromSha: 'abc'), throwsGit<GitAuthException>());
      expect(gh.calls, isEmpty);
    });

    test('an existing branch is reported with GitHub\'s words', () async {
      gh.on('POST', '$base/git/refs', status: 422, json: {'message': 'Reference already exists'});
      await expectLater(client.createBranch(repo, 'dev', fromSha: 'abc'), throwsPlainGit(equals('Reference already exists')));
    });
  });

  group('getTree', () {
    final recursiveTree = {
      'truncated': false,
      'tree': [
        {'path': 'README.md', 'type': 'blob', 'sha': 'b0'},
        {'path': 'apis', 'type': 'tree', 'sha': 't2'},
        {'path': 'apis/users', 'type': 'tree', 'sha': 't3'},
        {'path': 'apis/users/collection.json', 'type': 'blob', 'sha': 'b1'},
        {'path': 'apis/users-v2/collection.json', 'type': 'blob', 'sha': 'b2'},
        {'path': 'vendor', 'type': 'commit', 'sha': 'c9'},
      ],
    };

    test('resolves commit to tree, lists recursively and keeps only blobs under the prefix', () async {
      gh.on('GET', '$base/git/commits/c1', json: {'tree': {'sha': 't1'}});
      gh.on('GET', '$base/git/trees/t1', query: {'recursive': '1'}, json: recursiveTree);
      final tree = await client.getTree(repo, 'c1', pathPrefix: 'apis/users/');
      expect(tree.commitSha, 'c1');
      expect(tree.blobShaByPath, {'apis/users/collection.json': 'b1'});
      expect(gh.labels, ['GET $base/git/commits/c1', 'GET $base/git/trees/t1']);
    });

    test('an empty prefix lists every file and no directories or submodules', () async {
      gh.on('GET', '$base/git/commits/c1', json: {'tree': {'sha': 't1'}});
      gh.on('GET', '$base/git/trees/t1', query: {'recursive': '1'}, json: recursiveTree);
      final tree = await client.getTree(repo, 'c1');
      expect(tree.blobShaByPath, {
        'README.md': 'b0',
        'apis/users/collection.json': 'b1',
        'apis/users-v2/collection.json': 'b2',
      });
    });

    test('a truncated listing is rebuilt folder by folder, only where the prefix can match', () async {
      gh.on('GET', '$base/git/commits/c1', json: {'tree': {'sha': 't1'}});
      gh.on('GET', '$base/git/trees/t1', query: {'recursive': '1'}, json: {'truncated': true, 'tree': []});
      gh.on('GET', '$base/git/trees/t1', json: {
        'truncated': false,
        'tree': [
          {'path': 'README.md', 'type': 'blob', 'sha': 'b0'},
          {'path': 'apis', 'type': 'tree', 'sha': 't2'},
          {'path': 'docs', 'type': 'tree', 'sha': 't9'},
        ],
      });
      gh.on('GET', '$base/git/trees/t2', json: {
        'truncated': false,
        'tree': [
          {'path': 'other.json', 'type': 'blob', 'sha': 'b3'},
          {'path': 'users', 'type': 'tree', 'sha': 't3'},
          {'path': 'users-v2', 'type': 'tree', 'sha': 't4'},
          {'path': 'billing', 'type': 'tree', 'sha': 't5'},
        ],
      });
      gh.on('GET', '$base/git/trees/t3', json: {
        'truncated': false,
        'tree': [
          {'path': 'collection.json', 'type': 'blob', 'sha': 'b1'},
        ],
      });
      gh.on('GET', '$base/git/trees/t4', json: {
        'truncated': false,
        'tree': [
          {'path': 'collection.json', 'type': 'blob', 'sha': 'b2'},
        ],
      });

      final tree = await client.getTree(repo, 'c1', pathPrefix: 'apis/users');
      expect(tree.blobShaByPath, {
        'apis/users/collection.json': 'b1',
        'apis/users-v2/collection.json': 'b2',
      });
      final walked = gh.labels.where((l) => l.contains('/git/trees/')).toList();
      expect(walked, [
        'GET $base/git/trees/t1',
        'GET $base/git/trees/t1',
        'GET $base/git/trees/t2',
        'GET $base/git/trees/t3',
        'GET $base/git/trees/t4',
      ]);
      expect(gh.calls.where((c) => c.path.endsWith('/t1') && c.query.containsKey('recursive')), hasLength(1));
    });

    test('a folder GitHub cannot list is an error, not a silent partial result', () async {
      gh.on('GET', '$base/git/commits/c1', json: {'tree': {'sha': 't1'}});
      gh.on('GET', '$base/git/trees/t1', json: {'truncated': true, 'tree': []});
      await expectLater(client.getTree(repo, 'c1'), throwsPlainGit(contains('too many entries')));
    });

    test('an unknown commit is not found', () async {
      gh.on('GET', '$base/git/commits/c1', status: 404, json: {'message': 'Not Found'});
      await expectLater(client.getTree(repo, 'c1'), throwsGit<GitNotFoundException>(contains('Commit c1')));
    });
  });

  group('getBlobText', () {
    test('decodes base64 that GitHub wraps every 60 characters, including non-ASCII text', () async {
      const text = '{"name":"Zażółć gęślą jaźń ✓","url":"https://example.com/a?b=c"}';
      final encoded = base64Encode(utf8.encode(text));
      final wrapped = '${[for (var i = 0; i < encoded.length; i += 60) encoded.substring(i, min(i + 60, encoded.length))].join('\n')}\n';
      expect(wrapped, contains('\n'));
      gh.on('GET', '$base/git/blobs/b1', json: {'sha': 'b1', 'encoding': 'base64', 'content': wrapped});
      expect(await client.getBlobText(repo, 'b1'), text);
    });

    test('returns utf-8 content as it is', () async {
      gh.on('GET', '$base/git/blobs/b1', json: {'encoding': 'utf-8', 'content': 'plain text'});
      expect(await client.getBlobText(repo, 'b1'), 'plain text');
    });

    test('content that is not valid base64 is a host error, not a crash', () async {
      gh.on('GET', '$base/git/blobs/b1', json: {'encoding': 'base64', 'content': '!!!'});
      await expectLater(client.getBlobText(repo, 'b1'), throwsPlainGit());
    });
  });

  group('commit', () {
    void stubFlow({String head = 'p1', String branch = 'main'}) {
      gh.on('GET', '$base/git/ref/heads/$branch', json: {'object': {'sha': head}});
      gh.on('GET', '$base/git/commits/p1', json: {'tree': {'sha': 'baseTree'}});
      gh.on('POST', '$base/git/trees', status: 201, json: {'sha': 'newTree'});
      gh.on('POST', '$base/git/commits', status: 201, json: {'sha': 'c2'});
      gh.on('PATCH', '$base/git/refs/heads/$branch', json: {'object': {'sha': 'c2'}});
    }

    test('writes and deletions become one commit, in the documented call order', () async {
      stubFlow();
      final sha = await client.commit(
        repo,
        branch: 'main',
        parentSha: 'p1',
        message: 'Update users',
        changes: {'apis/users/collection.json': '{"a":1}', 'apis/old.json': null},
      );

      expect(sha, 'c2');
      expect(gh.labels, [
        'GET $base/git/ref/heads/main',
        'GET $base/git/commits/p1',
        'POST $base/git/trees',
        'POST $base/git/commits',
        'PATCH $base/git/refs/heads/main',
      ]);
      expect(gh.calls[2].body, {
        'base_tree': 'baseTree',
        'tree': [
          {'path': 'apis/users/collection.json', 'mode': '100644', 'type': 'blob', 'content': '{"a":1}'},
          {'path': 'apis/old.json', 'mode': '100644', 'type': 'blob', 'sha': null},
        ],
      });
      expect(gh.calls[2].raw, contains('"sha":null'));
      expect(gh.calls[3].body, {'message': 'Update users', 'tree': 'newTree', 'parents': ['p1']});
      expect(gh.calls[4].body, {'sha': 'c2', 'force': false});
    });

    test('a branch name with slashes is used as path segments in both ref calls', () async {
      stubFlow(branch: 'feature/x');
      await client.commit(repo, branch: 'feature/x', parentSha: 'p1', message: 'm', changes: {'a.json': 'A'});
      expect(gh.labels.first, 'GET $base/git/ref/heads/feature/x');
      expect(gh.labels.last, 'PATCH $base/git/refs/heads/feature/x');
    });

    test('a branch that moved is detected before anything is written', () async {
      gh.on('GET', '$base/git/ref/heads/main', json: {'object': {'sha': 'someone-else'}});
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: 'p1', message: 'm', changes: {'a.json': 'A'}),
        throwsGit<GitNotFastForwardException>(),
      );
      expect(gh.labels, ['GET $base/git/ref/heads/main']);
    });

    test('a branch deleted on GitHub is a non-fast-forward too', () async {
      gh.on('GET', '$base/git/ref/heads/main', status: 404, json: {'message': 'Not Found'});
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: 'p1', message: 'm', changes: {'a.json': 'A'}),
        throwsGit<GitNotFastForwardException>(contains('no longer exists')),
      );
    });

    test('GitHub refusing the ref update as not a fast forward is a non-fast-forward', () async {
      stubFlow();
      gh.on('PATCH', '$base/git/refs/heads/main', status: 422, json: {'message': 'Update is not a fast forward'});
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: 'p1', message: 'm', changes: {'a.json': 'A'}),
        throwsGit<GitNotFastForwardException>(),
      );
      expect(gh.labels.last, 'PATCH $base/git/refs/heads/main');
    });

    test('other ref update failures stay plain host errors', () async {
      stubFlow();
      gh.on('PATCH', '$base/git/refs/heads/main', status: 422, json: {'message': 'Reference does not exist'});
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: 'p1', message: 'm', changes: {'a.json': 'A'}),
        throwsPlainGit(equals('Reference does not exist')),
      );
    });

    test('needs a token and does not call GitHub without one', () async {
      creds.token = null;
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: 'p1', message: 'm', changes: {'a.json': 'A'}),
        throwsGit<GitAuthException>(equals('No GitHub token saved')),
      );
      expect(gh.calls, isEmpty);
    });

    test('an empty change set is a programming error', () async {
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: 'p1', message: 'm', changes: {}),
        throwsA(isA<ArgumentError>()),
      );
      expect(gh.calls, isEmpty);
    });
  });

  group('commit in a repository without commits', () {
    test('a single file goes through the contents API, which creates the commit and the branch', () async {
      gh.on('PUT', '$base/contents/apis/users/collection.json', status: 201, json: {'commit': {'sha': 'first'}});
      final sha = await client.commit(
        repo,
        branch: 'main',
        parentSha: '',
        message: 'Initial',
        changes: {'apis/users/collection.json': 'héllo', 'gone.json': null},
      );
      expect(sha, 'first');
      expect(gh.labels, ['PUT $base/contents/apis/users/collection.json']);
      expect(gh.calls.single.body, {'message': 'Initial', 'content': base64Encode(utf8.encode('héllo')), 'branch': 'main'});
    });

    test('remaining files continue on top of that commit, and deletions are ignored', () async {
      gh.on('PUT', '$base/contents/a.json', status: 201, json: {'commit': {'sha': 'first'}});
      gh.on('GET', '$base/git/commits/first', json: {'tree': {'sha': 'firstTree'}});
      gh.on('POST', '$base/git/trees', status: 201, json: {'sha': 'newTree'});
      gh.on('POST', '$base/git/commits', status: 201, json: {'sha': 'second'});
      gh.on('PATCH', '$base/git/refs/heads/main', json: {});

      final sha = await client.commit(
        repo,
        branch: 'main',
        parentSha: '',
        message: 'Initial',
        changes: {'a.json': 'A', 'gone.json': null, 'b.json': 'B'},
      );

      expect(sha, 'second');
      expect(gh.labels, [
        'PUT $base/contents/a.json',
        'GET $base/git/commits/first',
        'POST $base/git/trees',
        'POST $base/git/commits',
        'PATCH $base/git/refs/heads/main',
      ]);
      expect(gh.calls[2].body, {
        'base_tree': 'firstTree',
        'tree': [
          {'path': 'b.json', 'mode': '100644', 'type': 'blob', 'content': 'B'},
        ],
      });
      expect(gh.calls[3].body, {'message': 'Initial', 'tree': 'newTree', 'parents': ['first']});
      expect(gh.calls[4].body, {'sha': 'second', 'force': false});
    });

    test('only deletions leave nothing to write', () async {
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: '', message: 'm', changes: {'gone.json': null}),
        throwsA(isA<ArgumentError>()),
      );
      expect(gh.calls, isEmpty);
    });

    test('someone else creating the first commit meanwhile is a non-fast-forward', () async {
      gh.on('PUT', '$base/contents/a.json', status: 422, json: {'message': 'Invalid request.\n\n"sha" wasn\'t supplied.'});
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: '', message: 'm', changes: {'a.json': 'A'}),
        throwsGit<GitNotFastForwardException>(),
      );
    });

    test('a conflict on the first file is a non-fast-forward', () async {
      gh.on('PUT', '$base/contents/a.json', status: 409, json: {'message': 'Conflict'});
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: '', message: 'm', changes: {'a.json': 'A'}),
        throwsGit<GitNotFastForwardException>(),
      );
    });

    test('other failures on the first file stay plain host errors', () async {
      gh.on('PUT', '$base/contents/a.json', status: 422, json: {'message': 'path contains a malformed path component'});
      await expectLater(
        client.commit(repo, branch: 'main', parentSha: '', message: 'm', changes: {'a.json': 'A'}),
        throwsPlainGit(contains('malformed path')),
      );
    });
  });

  group('listCommits', () {
    test('maps commits and asks for the branch, folder and page size', () async {
      gh.on('GET', '$base/commits', json: [
        {
          'sha': 'abcdef1234567890',
          'html_url': 'https://github.com/octo/hello/commit/abcdef1234567890',
          'commit': {
            'message': 'Fix users\n\nlonger body',
            'author': {'name': 'Ada', 'date': '2026-09-01T10:20:30Z'},
          },
        },
        {
          'sha': '1234567abcdef',
          'commit': {
            'message': 'Init',
            'author': {'name': 'Bob', 'date': '2026-08-31T08:00:00Z'},
          },
        },
      ]);

      final commits = await client.listCommits(repo, branch: 'feature/x', pathPrefix: 'apis/users/', limit: 10);

      expect(commits, hasLength(2));
      expect(commits[0].sha, 'abcdef1234567890');
      expect(commits[0].title, 'Fix users');
      expect(commits[0].message, 'Fix users\n\nlonger body');
      expect(commits[0].authorName, 'Ada');
      expect(commits[0].date, DateTime.utc(2026, 9, 1, 10, 20, 30));
      expect(commits[0].url, 'https://github.com/octo/hello/commit/abcdef1234567890');
      expect(commits[1].url, isNull);
      final q = gh.calls.single.query;
      expect(q['sha'], 'feature/x');
      expect(q['path'], 'apis/users');
      expect(q['per_page'], '10');
    });

    test('sends no path without a prefix and clamps the page size', () async {
      gh.on('GET', '$base/commits', json: []);
      await client.listCommits(repo, branch: 'main', limit: 500);
      await client.listCommits(repo, branch: 'main', limit: 0);
      expect(gh.calls[0].query.containsKey('path'), isFalse);
      expect(gh.calls[0].query['per_page'], '100');
      expect(gh.calls[1].query['per_page'], '1');
    });

    test('an empty repository has no commits', () async {
      gh.on('GET', '$base/commits', status: 409, json: {'message': 'Git Repository is empty.'});
      expect(await client.listCommits(repo, branch: 'main'), isEmpty);
    });

    test('an unknown branch is not found', () async {
      gh.on('GET', '$base/commits', status: 404, json: {'message': 'No commit found for SHA: nope'});
      await expectLater(client.listCommits(repo, branch: 'nope'), throwsGit<GitNotFoundException>(contains('Branch "nope"')));
    });
  });

  group('listContributors', () {
    test('maps login, contributions and links', () async {
      gh.on('GET', '$base/contributors', json: [
        {'login': 'ada', 'contributions': 12, 'avatar_url': 'https://avatars/ada', 'html_url': 'https://github.com/ada'},
        {'login': 'bob', 'contributions': 3},
      ]);
      final people = await client.listContributors(repo);
      expect(people.map((c) => c.login), ['ada', 'bob']);
      expect(people[0].contributions, 12);
      expect(people[0].avatarUrl, 'https://avatars/ada');
      expect(people[0].profileUrl, 'https://github.com/ada');
      expect(people[1].avatarUrl, isNull);
      expect(gh.calls.single.query['per_page'], '50');
    });

    test('204 with no body is an empty list', () async {
      gh.on('GET', '$base/contributors', status: 204);
      expect(await client.listContributors(repo), isEmpty);
    });
  });

  group('error mapping', () {
    Future<GitRepoInfo> probe() => client.getRepo(repo);

    void reply(int status, {Object? json, String? raw, Map<String, String> headers = const {}}) =>
        gh.on('GET', base, status: status, json: json, raw: raw, headers: headers);

    test('401 is an auth failure carrying GitHub\'s message', () async {
      reply(401, json: {'message': 'Bad credentials'});
      await expectLater(probe(), throwsGit<GitAuthException>(contains('Bad credentials')));
    });

    test('403 bad credentials is an auth failure', () async {
      reply(403, json: {'message': 'Bad credentials'});
      await expectLater(probe(), throwsGit<GitAuthException>());
    });

    test('403 SAML enforcement is an auth failure', () async {
      reply(403, json: {'message': 'Resource protected by organization SAML enforcement. You must grant your Personal Access token access to this organization.'});
      await expectLater(probe(), throwsGit<GitAuthException>(contains('SAML')));
    });

    test('403 for a token without access is an auth failure', () async {
      reply(403, json: {'message': 'Resource not accessible by personal access token'});
      await expectLater(probe(), throwsGit<GitAuthException>());
    });

    test('403 with X-RateLimit-Remaining 0 is a rate limit and names the reset time', () async {
      final reset = DateTime(2030, 1, 1, 13, 5).millisecondsSinceEpoch ~/ 1000;
      reply(403, json: {'message': 'Forbidden'}, headers: {'X-RateLimit-Remaining': '0', 'X-RateLimit-Reset': '$reset'});
      await expectLater(probe(), throwsGit<GitRateLimitException>(allOf(contains('rate limit'), contains('13:05'))));
    });

    test('403 mentioning the rate limit is a rate limit even without the headers', () async {
      reply(403, json: {'message': 'API rate limit exceeded for 203.0.113.9.'});
      await expectLater(probe(), throwsGit<GitRateLimitException>(contains('Try again later')));
    });

    test('a secondary limit with Retry-After says how long to wait', () async {
      reply(403, json: {'message': 'You have exceeded a secondary rate limit.'}, headers: {'Retry-After': '30'});
      await expectLater(probe(), throwsGit<GitRateLimitException>(contains('in 30s')));
    });

    test('429 is a rate limit', () async {
      reply(429, json: {'message': 'Too Many Requests'});
      await expectLater(probe(), throwsGit<GitRateLimitException>());
    });

    test('anonymous callers are told a token raises the limit', () async {
      creds.token = null;
      reply(403, json: {'message': 'API rate limit exceeded'});
      await expectLater(probe(), throwsGit<GitRateLimitException>(contains('Saving a GitHub token')));
    });

    test('any other 403 is a plain host error with GitHub\'s message', () async {
      reply(403, json: {'message': 'Repository access blocked'});
      await expectLater(probe(), throwsPlainGit(equals('Repository access blocked')));
    });

    test('404 says the resource is missing or invisible to the token', () async {
      reply(404, json: {'message': 'Not Found'});
      await expectLater(probe(), throwsGit<GitNotFoundException>(endsWith('not found, or your token cannot see it')));
    });

    test('5xx uses the message GitHub sent', () async {
      reply(502, json: {'message': 'Server Error'});
      await expectLater(probe(), throwsPlainGit(equals('Server Error')));
    });

    test('a bodyless or non-JSON failure falls back to the status code', () async {
      reply(500);
      await expectLater(probe(), throwsPlainGit(equals('GitHub returned 500')));
    });

    test('a non-JSON error page falls back to the status code', () async {
      reply(502, raw: '<html>Bad gateway</html>');
      await expectLater(probe(), throwsPlainGit(equals('GitHub returned 502')));
    });

    test('network errors say GitHub could not be reached', () async {
      gh.on('GET', base, fail: DioExceptionType.connectionError);
      await expectLater(probe(), throwsPlainGit(startsWith('Could not reach GitHub')));
    });

    test('timeouts say GitHub could not be reached', () async {
      gh.on('GET', base, fail: DioExceptionType.receiveTimeout);
      await expectLater(probe(), throwsPlainGit(allOf(startsWith('Could not reach GitHub'), contains('timed out'))));
    });

    test('a success reply that is not the expected JSON is a host error, not a crash', () async {
      reply(200, raw: '<html>captive portal</html>');
      await expectLater(probe(), throwsPlainGit(contains('could not read')));
    });
  });

  group('SecureGitCredentialsStore', () {
    test('keeps the token under a per-provider key', () async {
      final values = <String, String>{};
      FlutterSecureStorage.setMockInitialValues(values);
      final store = SecureGitCredentialsStore();

      expect(await store.readToken(GitProvider.github), isNull);
      await store.saveToken(GitProvider.github, 'ghp_1');
      expect(values, {'git_token_github': 'ghp_1'});
      expect(await store.readToken(GitProvider.github), 'ghp_1');
      await store.deleteToken(GitProvider.github);
      expect(values, isEmpty);
      expect(await store.readToken(GitProvider.github), isNull);
    });

    test('falls back to memory for the session when secure storage throws', () async {
      final store = SecureGitCredentialsStore(storage: _BrokenStorage());

      expect(await store.readToken(GitProvider.github), isNull);
      await store.saveToken(GitProvider.github, 'ghp_1');
      expect(await store.readToken(GitProvider.github), 'ghp_1');
      await store.deleteToken(GitProvider.github);
      expect(await store.readToken(GitProvider.github), isNull);
    });
  });
}
