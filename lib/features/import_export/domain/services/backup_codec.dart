import 'dart:convert';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../defaults/domain/entities/defaults_chain.dart';
import '../../../defaults/domain/entities/level_defaults.dart';
import '../../../defaults/domain/services/defaults_codec.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/entities/global_variable_entity.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../settings/domain/entities/request_settings.dart';

/// The description (Markdown) and tags of a collection, folder or request.
final class BackupNotes {
  final String description;
  final List<String> tags;
  const BackupNotes({this.description = '', this.tags = const []});

  static const none = BackupNotes();

  bool get isEmpty => description.isEmpty && tags.isEmpty;
}

/// One doc of a linked collection's last-synced Git state: where it lived in
/// the repository, the blob sha of that file, and the doc itself as the JSON
/// text the sync engine stored (kept verbatim, so merges see exactly what they
/// saw before).
final class BackupGitBase {
  final String uid;
  final String path;
  final String blobSha;
  final String doc;
  const BackupGitBase({required this.uid, required this.path, required this.blobSha, required this.doc});
}

/// A collection's link to a Git repository and what it last shared with it.
/// Carried in a workspace file so that switching workplaces, or rebuilding the
/// database from the file, does not silently unlink the collection. No access
/// token is ever part of it.
final class BackupGit {
  final String provider;
  final String owner;
  final String repo;
  final String branch;
  final String basePath;
  final String? lastSyncedSha;
  final DateTime? lastSyncedAt;
  final bool includeSecrets;
  final List<BackupGitBase> base;

  const BackupGit({
    required this.provider,
    required this.owner,
    required this.repo,
    required this.branch,
    this.basePath = '',
    this.lastSyncedSha,
    this.lastSyncedAt,
    this.includeSecrets = false,
    this.base = const [],
  });
}

/// A request with the rows that hang off it. Only the request's own fields
/// are meaningful: its ids are placeholders, except [FolderEntity.id] which is
/// the file-local id that folders and requests refer to.
final class BackupRequest {
  final ApiRequestEntity request;
  final RequestScriptsEntity? scripts;
  final List<ResponseExampleEntity> examples;

  /// Per-request overrides (redirects, TLS verification, timeout, no-cache);
  /// null when the request has none.
  final RequestSettings? settings;
  final BackupNotes notes;

  /// The uid that identifies this request in a Git repository; only present in
  /// a collection that is linked to one.
  final String? uid;

  const BackupRequest({
    required this.request,
    this.scripts,
    this.examples = const [],
    this.settings,
    this.notes = BackupNotes.none,
    this.uid,
  });
}

final class BackupCollection {
  final String name;
  final RequestAuth? auth;
  final List<CollectionVariableEntity> variables;
  final List<FolderEntity> folders;
  final List<BackupRequest> requests;
  final BackupNotes notes;

  /// Descriptions and tags of the [folders], by their file-local id.
  final Map<int, BackupNotes> folderNotes;

  /// Set only for a collection linked to a Git repository: [git] is the link,
  /// [uid] and [folderUids] (by file-local folder id) identify the collection and
  /// its folders in that repository (requests carry theirs in [BackupRequest.uid]).
  final BackupGit? git;
  final String? uid;
  final Map<int, String> folderUids;

  /// What the collection passes down to every request: its headers and tests. Its own [auth] and
  /// [variables] are the fields above, so they are not repeated in here.
  final LevelDefaults defaults;

  /// What each folder passes down, by file-local folder id. A folder that sets nothing has no entry.
  final Map<int, LevelDefaults> folderDefaults;

  const BackupCollection({
    required this.name,
    this.auth,
    this.variables = const [],
    this.folders = const [],
    this.requests = const [],
    this.notes = BackupNotes.none,
    this.folderNotes = const {},
    this.git,
    this.uid,
    this.folderUids = const {},
    this.defaults = LevelDefaults.empty,
    this.folderDefaults = const {},
  });

  /// Whether the collection or one of its folders passes anything down.
  bool get hasDefaults => !defaults.isEmpty || folderDefaults.values.any((d) => !d.isEmpty);

  /// Every level of this collection, for resolving what a request inherits the way the app does
  /// (see `DefaultsResolver`). The collection's auth takes part as the level above the folders.
  DefaultsTree get defaultsTree => DefaultsTree(
        collectionName: name,
        collection: defaults.withAuth(auth == null ? null : DefaultsCodec.authFromJson(auth!.toJson())),
        folders: folders,
        folderDefaults: folderDefaults,
      );
}

final class BackupEnvironment {
  final String name;
  final List<EnvironmentVariableEntity> variables;
  const BackupEnvironment({required this.name, this.variables = const []});
}

/// Everything a backup file holds.
final class BackupSnapshot {
  final DateTime exportedAt;
  final List<BackupCollection> collections;
  final List<BackupEnvironment> environments;
  final List<GlobalVariableEntity> globals;

  const BackupSnapshot({
    required this.exportedAt,
    this.collections = const [],
    this.environments = const [],
    this.globals = const [],
  });
}

/// The backup file format: one versioned JSON document. Secret values
/// (environment and global variables, auth tokens, passwords) are written in
/// plain text, so the file says so itself (`"sensitive": true` and a notice).
/// Database ids never reach the file; folders carry a file-local `id` that
/// their children point at, which a restore remaps to fresh ids.
///
/// Version 2 added descriptions and tags (collections, folders, requests) and
/// per-request settings; a version 1 file has none of them and still reads.
/// Version 3 adds, for Git-linked collections only, the link and its sync state
/// (see [BackupGit]); it is written only when a file actually carries them, so
/// every other file stays readable by older apps, which refuse a version 3 file
/// loudly instead of quietly dropping the links.
/// Version 4 adds the defaults a collection and its folders pass down to their
/// requests (headers, tests and, on folders, variables and auth: the keys
/// `headers`, `tests`, `variables`, `auth` on the collection's and folder's
/// map, see `DefaultsCodec`); likewise written only when a file carries some,
/// so an older app refuses it instead of quietly dropping them. Versions 1 to
/// 3 still read, with no defaults.
abstract final class BackupCodec {
  static const formatId = 'postpilot-backup';
  static const currentVersion = 2;
  static const gitVersion = 3;
  static const defaultsVersion = 4;

  /// The newest version this app reads.
  static const maxVersion = defaultsVersion;
  static const _notice =
      'This file contains secrets (variable values, tokens, passwords, API keys) in plain text. Keep it private.';

  /// [includeGit] adds the Git link and sync state of linked collections. The
  /// backup a user exports leaves them out; a workspace file mirrored from the
  /// database needs them.
  static String encode(BackupSnapshot snapshot, {bool includeGit = false}) {
    final withGit = includeGit && snapshot.collections.any((c) => c.git != null);
    final withDefaults = snapshot.collections.any((c) => c.hasDefaults);
    return const JsonEncoder.withIndent('  ').convert({
      'format': formatId,
      'version': withDefaults ? defaultsVersion : (withGit ? gitVersion : currentVersion),
      'sensitive': true,
      'notice': _notice,
      'exportedAt': snapshot.exportedAt.toUtc().toIso8601String(),
      'collections': [for (final c in snapshot.collections) _encodeCollection(c, includeGit)],
      'environments': [
        for (final e in snapshot.environments)
          {
            'name': e.name,
            'variables': [
              for (final v in e.variables) {'key': v.key, 'value': v.value, 'secret': v.isSecret, 'enabled': v.enabled},
            ],
          },
      ],
      'globals': [
        for (final g in snapshot.globals) {'key': g.key, 'value': g.value, 'secret': g.isSecret, 'enabled': g.enabled},
      ],
    });
  }

  static Map<String, dynamic> _encodeCollection(BackupCollection c, bool includeGit) {
    final git = includeGit ? c.git : null;
    return {
      'name': c.name,
      ..._encodeNotes(c.notes),
      'uid': ?(git == null ? null : c.uid),
      'git': ?(git == null ? null : _encodeGit(git)),
      'auth': ?c.auth?.toJson(),
      'variables': [
        for (final v in c.variables) {'key': v.key, 'value': v.value, 'enabled': v.enabled},
      ],
      // The collection's own auth and variables are the two keys above.
      ...DefaultsCodec.toDoc(c.defaults, includeVariablesAndAuth: false),
      'folders': [
        for (final f in c.folders)
          {
            'id': f.id,
            'parentId': f.parentFolderId,
            'name': f.name,
            // Where it sits among the folders and requests of its parent. Optional on reading: a file without it
            // lists folders first, then requests, in file order.
            'order': f.orderIndex,
            ..._encodeNotes(c.folderNotes[f.id] ?? BackupNotes.none),
            'uid': ?(git == null ? null : c.folderUids[f.id]),
            ...DefaultsCodec.toDoc(c.folderDefaults[f.id] ?? LevelDefaults.empty),
          },
      ],
      'requests': [for (final r in c.requests) _encodeRequest(r, includeGit && git != null)],
    };
  }

  static Map<String, dynamic> _encodeGit(BackupGit g) => {
    'provider': g.provider,
    'owner': g.owner,
    'repo': g.repo,
    'branch': g.branch,
    'basePath': g.basePath,
    'lastSyncedSha': g.lastSyncedSha,
    'lastSyncedAt': g.lastSyncedAt?.toUtc().toIso8601String(),
    'includeSecrets': g.includeSecrets,
    'base': [
      for (final b in g.base) {'uid': b.uid, 'path': b.path, 'blobSha': b.blobSha, 'doc': b.doc},
    ],
  };

  /// Only the parts that are set, so an undocumented entity adds no keys.
  static Map<String, dynamic> _encodeNotes(BackupNotes notes) => {
    if (notes.description.isNotEmpty) 'description': notes.description,
    if (notes.tags.isNotEmpty) 'tags': notes.tags,
  };

  static Map<String, dynamic> _encodeRequest(BackupRequest r, bool includeGit) {
    final q = r.request;
    final scripts = r.scripts;
    final settings = r.settings;
    return {
      'folderId': q.folderId,
      'name': q.name,
      'order': q.orderIndex,
      ..._encodeNotes(r.notes),
      'uid': ?(includeGit ? r.uid : null),
      'method': q.method.name,
      'url': q.url,
      'headers': _encodeItems(q.headers),
      'queryParams': _encodeItems(q.queryParams),
      'body': {
        'type': q.body.type.name,
        'rawContentType': q.body.rawContentType.name,
        'rawText': q.body.rawText,
        'formFields': _encodeItems(q.body.formFields),
        'urlEncodedFields': _encodeItems(q.body.urlEncodedFields),
        'graphqlQuery': q.body.graphqlQuery,
        'graphqlVariables': q.body.graphqlVariables,
      },
      'auth': q.auth.toJson(),
      if (settings != null && !settings.isEmpty) 'settings': settings.toJson(),
      if (scripts != null)
        'scripts': {
          'assertions': _decodeJsonList(scripts.assertionsJson),
          'extractors': _decodeJsonList(scripts.extractorsJson),
        },
      if (r.examples.isNotEmpty)
        'examples': [
          for (final e in r.examples)
            {
              'name': e.name,
              'statusCode': e.statusCode,
              'headers': e.headers,
              'body': e.body,
              'savedAt': e.savedAt.toUtc().toIso8601String(),
            },
        ],
    };
  }

  static List<Map<String, dynamic>> _encodeItems(List<KeyValueItem> items) => [
    for (final i in items) {'key': i.key, 'value': i.value, 'enabled': i.enabled},
  ];

  /// The scripts columns are JSON arrays kept as text; the file embeds them
  /// as real arrays instead of doubly-escaped strings.
  static List<dynamic> _decodeJsonList(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is List ? decoded : const [];
    } on FormatException {
      return const [];
    }
  }

  static BackupSnapshot decode(String text) {
    final Object? root;
    try {
      root = jsonDecode(text.replaceFirst('﻿', '').trim());
    } on FormatException {
      throw const ImportException('the text is not valid JSON.');
    }
    if (root is! Map || root['format'] != formatId) {
      throw const ImportException('the "format" marker of a PostPilot backup is missing.');
    }
    final version = root['version'];
    if (version is! int || version < 1) throw const ImportException('the backup has no valid version number.');
    if (version > maxVersion) {
      throw ImportException(
        'it was made by a newer PostPilot (backup version $version; this app reads up to $maxVersion).',
      );
    }
    try {
      return BackupSnapshot(
        exportedAt: DateTime.tryParse('${root['exportedAt'] ?? ''}') ?? DateTime.now(),
        collections: [for (final c in _maps(root['collections'])) _decodeCollection(c)],
        environments: [for (final e in _maps(root['environments'])) _decodeEnvironment(e)],
        globals: [
          for (final g in _maps(root['globals']))
            if (_text(g['key']).isNotEmpty)
              GlobalVariableEntity(
                id: 0,
                key: _text(g['key']),
                value: _text(g['value']),
                isSecret: g['secret'] == true,
                enabled: g['enabled'] != false,
              ),
        ],
      );
    } on TypeError {
      throw const ImportException('the backup is damaged (a field has an unexpected type).');
    }
  }

  static BackupCollection _decodeCollection(Map<String, dynamic> c) {
    final git = _decodeGit(c['git']);
    final folderMaps = [for (final f in _maps(c['folders'])) if (f['id'] is int) f];
    final requestMaps = _maps(c['requests']);
    final orders = _decodeOrders(folderMaps, requestMaps);
    return BackupCollection(
      git: git,
      // uids mean nothing without the link they belong to
      uid: git != null && c['uid'] is String ? c['uid'] as String : null,
      folderUids: {
        if (git != null)
          for (final f in _maps(c['folders']))
            if (f['id'] is int && f['uid'] is String) f['id'] as int: f['uid'] as String,
      },
      name: _name(c['name'], 'Restored collection'),
      auth: c['auth'] is Map ? RequestAuth.fromJson(_map(c['auth'])) : null,
      notes: _decodeNotes(c),
      variables: [
        for (final v in _maps(c['variables']))
          if (_text(v['key']).isNotEmpty)
            CollectionVariableEntity(
              id: 0,
              collectionId: 0,
              key: _text(v['key']),
              value: _text(v['value']),
              enabled: v['enabled'] != false,
            ),
      ],
      folders: [
        for (final (i, f) in folderMaps.indexed)
          FolderEntity(
            id: f['id'] as int,
            collectionId: 0,
            parentFolderId: f['parentId'] is int ? f['parentId'] as int : null,
            name: _name(f['name'], 'Folder'),
            orderIndex: orders.folders[i],
          ),
      ],
      folderNotes: {
        for (final f in _maps(c['folders']))
          if (f['id'] is int && !_decodeNotes(f).isEmpty) f['id'] as int: _decodeNotes(f),
      },
      requests: [
        for (final (i, r) in requestMaps.indexed) _decodeRequest(r, withUid: git != null, order: orders.requests[i]),
      ],
      defaults: DefaultsCodec.fromDoc(c, includeVariablesAndAuth: false),
      folderDefaults: {
        for (final f in _maps(c['folders']))
          if (f['id'] is int && !DefaultsCodec.fromDoc(f).isEmpty) f['id'] as int: DefaultsCodec.fromDoc(f),
      },
    );
  }

  /// The position of every folder and request. A level in which every entry has an integer `order` keeps those.
  /// Any other level (a file from before `order` was written) lists its folders first and then its requests,
  /// each in file order: the way such a collection has always been shown.
  static ({List<int> folders, List<int> requests}) _decodeOrders(
    List<Map<String, dynamic>> folders,
    List<Map<String, dynamic>> requests,
  ) {
    final folderLevels = <int?, List<int>>{};
    final requestLevels = <int?, List<int>>{};
    for (var i = 0; i < folders.length; i++) {
      final parent = folders[i]['parentId'];
      (folderLevels[parent is int ? parent : null] ??= []).add(i);
    }
    for (var i = 0; i < requests.length; i++) {
      final parent = requests[i]['folderId'];
      (requestLevels[parent is int ? parent : null] ??= []).add(i);
    }
    final folderOrders = List<int>.filled(folders.length, 0);
    final requestOrders = List<int>.filled(requests.length, 0);
    for (final parent in {...folderLevels.keys, ...requestLevels.keys}) {
      final inFolders = folderLevels[parent] ?? const <int>[];
      final inRequests = requestLevels[parent] ?? const <int>[];
      final explicit = [
        for (final i in inFolders) folders[i]['order'],
        for (final i in inRequests) requests[i]['order'],
      ].every((order) => order is int);
      var next = 0;
      for (final i in inFolders) {
        folderOrders[i] = explicit ? folders[i]['order'] as int : next++;
      }
      for (final i in inRequests) {
        requestOrders[i] = explicit ? requests[i]['order'] as int : next++;
      }
    }
    return (folders: folderOrders, requests: requestOrders);
  }

  /// A damaged section is dropped whole: half a link (or a base missing some
  /// docs) would make the next sync mistake untouched docs for new or deleted ones.
  static BackupGit? _decodeGit(dynamic raw) {
    if (raw is! Map) return null;
    final g = raw.cast<String, dynamic>();
    String? text(String key) => g[key] is String && (g[key] as String).isNotEmpty ? g[key] as String : null;
    final provider = text('provider');
    final owner = text('owner');
    final repo = text('repo');
    final branch = text('branch');
    if (provider == null || owner == null || repo == null || branch == null) return null;
    final base = <BackupGitBase>[];
    if (g['base'] != null && g['base'] is! List) return null;
    for (final entry in (g['base'] as List? ?? const [])) {
      if (entry is! Map ||
          entry['uid'] is! String ||
          entry['path'] is! String ||
          entry['blobSha'] is! String ||
          entry['doc'] is! String) {
        return null;
      }
      base.add(
        BackupGitBase(
          uid: entry['uid'] as String,
          path: entry['path'] as String,
          blobSha: entry['blobSha'] as String,
          doc: entry['doc'] as String,
        ),
      );
    }
    return BackupGit(
      provider: provider,
      owner: owner,
      repo: repo,
      branch: branch,
      basePath: g['basePath'] is String ? g['basePath'] as String : '',
      lastSyncedSha: g['lastSyncedSha'] is String ? g['lastSyncedSha'] as String : null,
      lastSyncedAt: DateTime.tryParse('${g['lastSyncedAt'] ?? ''}'),
      includeSecrets: g['includeSecrets'] == true,
      base: base,
    );
  }

  static BackupNotes _decodeNotes(Map<String, dynamic> map) => BackupNotes(
    description: map['description'] is String ? map['description'] as String : '',
    tags: [
      if (map['tags'] is List)
        for (final tag in map['tags'] as List)
          if (tag is String && tag.trim().isNotEmpty) tag,
    ],
  );

  static BackupRequest _decodeRequest(Map<String, dynamic> r, {bool withUid = false, int order = 0}) {
    final scripts = r['scripts'];
    final settings = r['settings'] is Map ? RequestSettings.fromJson(_map(r['settings'])) : null;
    return BackupRequest(
      uid: withUid && r['uid'] is String ? r['uid'] as String : null,
      notes: _decodeNotes(r),
      settings: settings == null || settings.isEmpty ? null : settings,
      request: ApiRequestEntity(
        id: 0,
        collectionId: 0,
        folderId: r['folderId'] is int ? r['folderId'] as int : null,
        name: _name(r['name'], 'Untitled request'),
        method: HttpMethod.fromString(_text(r['method'])),
        url: _text(r['url']),
        headers: _decodeItems(r['headers']),
        queryParams: _decodeItems(r['queryParams']),
        body: _decodeBody(_map(r['body'])),
        auth: r['auth'] is Map ? RequestAuth.fromJson(_map(r['auth'])) : const RequestAuth(),
        orderIndex: order,
      ),
      scripts: scripts is Map
          ? RequestScriptsEntity(
              requestId: 0,
              assertionsJson: jsonEncode(scripts['assertions'] is List ? scripts['assertions'] : const []),
              extractorsJson: jsonEncode(scripts['extractors'] is List ? scripts['extractors'] : const []),
            )
          : null,
      examples: [
        for (final e in _maps(r['examples']))
          ResponseExampleEntity(
            id: 0,
            requestId: 0,
            name: _name(e['name'], 'Example'),
            statusCode: e['statusCode'] is int ? e['statusCode'] as int : 200,
            headers: {for (final h in _map(e['headers']).entries) h.key: _text(h.value)},
            body: _text(e['body']),
            savedAt: DateTime.tryParse(_text(e['savedAt'])) ?? DateTime.now(),
          ),
      ],
    );
  }

  static RequestBody _decodeBody(Map<String, dynamic> b) => RequestBody(
    type: _enumByName(BodyType.values, b['type'], BodyType.none),
    rawContentType: _enumByName(RawContentType.values, b['rawContentType'], RawContentType.json),
    rawText: _text(b['rawText']),
    formFields: _decodeItems(b['formFields']),
    urlEncodedFields: _decodeItems(b['urlEncodedFields']),
    graphqlQuery: _text(b['graphqlQuery']),
    graphqlVariables: b['graphqlVariables'] is String ? b['graphqlVariables'] as String : '{}',
  );

  static BackupEnvironment _decodeEnvironment(Map<String, dynamic> e) => BackupEnvironment(
    name: _name(e['name'], 'Restored environment'),
    variables: [
      for (final v in _maps(e['variables']))
        if (_text(v['key']).isNotEmpty)
          EnvironmentVariableEntity(
            id: 0,
            environmentId: 0,
            key: _text(v['key']),
            value: _text(v['value']),
            isSecret: v['secret'] == true,
            enabled: v['enabled'] != false,
          ),
    ],
  );

  static List<KeyValueItem> _decodeItems(dynamic list) => [
    for (final i in _maps(list))
      KeyValueItem(key: _text(i['key']), value: _text(i['value']), enabled: i['enabled'] != false),
  ];

  static T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  static List<Map<String, dynamic>> _maps(dynamic list) => [
    if (list is List)
      for (final e in list)
        if (e is Map) e.cast<String, dynamic>(),
  ];

  static Map<String, dynamic> _map(dynamic value) => value is Map ? value.cast<String, dynamic>() : const {};
  static String _text(dynamic value) => value == null ? '' : '$value';
  static String _name(dynamic value, String fallback) => value is String && value.trim().isNotEmpty ? value : fallback;
}
