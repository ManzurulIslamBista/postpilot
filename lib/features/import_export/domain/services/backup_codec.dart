import 'dart:convert';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
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

  const BackupRequest({
    required this.request,
    this.scripts,
    this.examples = const [],
    this.settings,
    this.notes = BackupNotes.none,
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

  const BackupCollection({
    required this.name,
    this.auth,
    this.variables = const [],
    this.folders = const [],
    this.requests = const [],
    this.notes = BackupNotes.none,
    this.folderNotes = const {},
  });
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
abstract final class BackupCodec {
  static const formatId = 'postpilot-backup';
  static const currentVersion = 2;
  static const _notice =
      'This file contains secrets (variable values, tokens, passwords, API keys) in plain text. Keep it private.';

  static String encode(BackupSnapshot snapshot) => const JsonEncoder.withIndent('  ').convert({
        'format': formatId,
        'version': currentVersion,
        'sensitive': true,
        'notice': _notice,
        'exportedAt': snapshot.exportedAt.toUtc().toIso8601String(),
        'collections': [for (final c in snapshot.collections) _encodeCollection(c)],
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

  static Map<String, dynamic> _encodeCollection(BackupCollection c) => {
        'name': c.name,
        ..._encodeNotes(c.notes),
        'auth': ?c.auth?.toJson(),
        'variables': [
          for (final v in c.variables) {'key': v.key, 'value': v.value, 'enabled': v.enabled},
        ],
        'folders': [
          for (final f in c.folders)
            {'id': f.id, 'parentId': f.parentFolderId, 'name': f.name, ..._encodeNotes(c.folderNotes[f.id] ?? BackupNotes.none)},
        ],
        'requests': [for (final r in c.requests) _encodeRequest(r)],
      };

  /// Only the parts that are set, so an undocumented entity adds no keys.
  static Map<String, dynamic> _encodeNotes(BackupNotes notes) => {
        if (notes.description.isNotEmpty) 'description': notes.description,
        if (notes.tags.isNotEmpty) 'tags': notes.tags,
      };

  static Map<String, dynamic> _encodeRequest(BackupRequest r) {
    final q = r.request;
    final scripts = r.scripts;
    final settings = r.settings;
    return {
      'folderId': q.folderId,
      'name': q.name,
      ..._encodeNotes(r.notes),
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
    if (version > currentVersion) {
      throw ImportException('it was made by a newer PostPilot (backup version $version; this app reads up to $currentVersion).');
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

  static BackupCollection _decodeCollection(Map<String, dynamic> c) => BackupCollection(
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
          for (final f in _maps(c['folders']))
            if (f['id'] is int)
              FolderEntity(
                id: f['id'] as int,
                collectionId: 0,
                parentFolderId: f['parentId'] is int ? f['parentId'] as int : null,
                name: _name(f['name'], 'Folder'),
              ),
        ],
        folderNotes: {
          for (final f in _maps(c['folders']))
            if (f['id'] is int && !_decodeNotes(f).isEmpty) f['id'] as int: _decodeNotes(f),
        },
        requests: [for (final r in _maps(c['requests'])) _decodeRequest(r)],
      );

  static BackupNotes _decodeNotes(Map<String, dynamic> map) => BackupNotes(
        description: map['description'] is String ? map['description'] as String : '',
        tags: [
          if (map['tags'] is List)
            for (final tag in map['tags'] as List)
              if (tag is String && tag.trim().isNotEmpty) tag,
        ],
      );

  static BackupRequest _decodeRequest(Map<String, dynamic> r) {
    final scripts = r['scripts'];
    final settings = r['settings'] is Map ? RequestSettings.fromJson(_map(r['settings'])) : null;
    return BackupRequest(
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
