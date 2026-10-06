// What a collection and its folders pass down can hold credentials: the split keeps them out of the shared file.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/workplace/domain/services/secret_splitter.dart';

KeyValueItem _h(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

const _token = 'tok_live_9f8e7d6c5b4a39281706fedcba';
const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.c2lnbmF0dXJl';

Map<String, dynamic> _doc({bool withUids = false}) {
  final snapshot = BackupSnapshot(
    exportedAt: DateTime.utc(2026),
    collections: [
      BackupCollection(
        name: 'Shop',
        uid: withUids ? 'c-uid' : null,
        git: withUids ? const BackupGit(provider: 'github', owner: 'o', repo: 'r', branch: 'main') : null,
        folderUids: withUids ? const {1: 'f1-uid', 2: 'f2-uid'} : const {},
        folders: const [
          FolderEntity(id: 1, collectionId: 0, parentFolderId: null, name: 'Orders'),
          FolderEntity(id: 2, collectionId: 0, parentFolderId: 1, name: 'Archive'),
        ],
        defaults: LevelDefaults(
          headers: [
            _h('X-Tenant', 'acme'),
            _h('Authorization', 'Bearer $_token'),
            _h('X-Api-Key', 'key-1234567890'),
            _h('X-Template', 'Bearer {{apiToken}}'),
          ],
          assertions: [
            AssertionEntity(type: AssertionType.headerEquals, path: 'Authorization', expected: 'Bearer response-secret'),
            AssertionEntity(type: AssertionType.statusEquals, expected: '200'),
          ],
        ),
        folderDefaults: {
          1: LevelDefaults(
            headers: [_h('Cookie', 'session=abc123def456')],
            variables: [
              DefaultVariable(key: 'region', value: 'eu'),
              DefaultVariable(key: 'tenantKey', value: 'plain-looking-value', isSecret: true),
              DefaultVariable(key: 'db_password', value: 'hunter2'),
            ],
            auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'orders-bearer-token'),
          ),
          2: const LevelDefaults(
            auth: RequestAuth(type: AuthType.basic, basicUsername: 'ann', basicPassword: 'pw-archive'),
          ),
        },
      ),
    ],
  );
  return jsonDecode(BackupCodec.encode(snapshot, includeGit: withUids)) as Map<String, dynamic>;
}

Map<String, dynamic> _collection(Map<String, dynamic> doc) => (doc['collections'] as List).single as Map<String, dynamic>;

Map<String, dynamic> _folder(Map<String, dynamic> doc, String name) =>
    (_collection(doc)['folders'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['name'] == name);

String _value(List items, String key) => (items.cast<Map>().firstWhere((i) => i['key'] == key))['value'] as String;

void main() {
  test('credentials in default headers, folder variables, folder auth and default checks are moved out', () {
    final split = SecretSplitter.split(_doc());
    final shop = _collection(split.publicDoc);

    final headers = shop['headers'] as List;
    expect(_value(headers, 'X-Tenant'), 'acme', reason: 'an ordinary header stays in the shared file');
    expect(_value(headers, 'Authorization'), '');
    expect(_value(headers, 'X-Api-Key'), '');
    expect(_value(headers, 'X-Template'), 'Bearer {{apiToken}}', reason: 'a header that only references a variable holds no secret');

    final checks = (shop['tests']['assertions'] as List).cast<Map>();
    expect(checks.firstWhere((a) => a['type'] == 'headerEquals')['expected'], '');
    expect(checks.firstWhere((a) => a['type'] == 'statusEquals')['expected'], '200');

    final orders = _folder(split.publicDoc, 'Orders');
    expect(_value(orders['headers'] as List, 'Cookie'), '');
    expect(_value(orders['variables'] as List, 'region'), 'eu');
    expect(_value(orders['variables'] as List, 'tenantKey'), '', reason: 'a variable marked secret');
    expect(_value(orders['variables'] as List, 'db_password'), '', reason: 'a variable named like a credential');
    expect(orders['auth']['bearerToken'], '');
    expect(orders['auth']['type'], 'bearer', reason: 'what kind of auth it is stays readable');

    final archive = _folder(split.publicDoc, 'Archive');
    expect(archive['auth']['basicPassword'], '');
    expect(archive['auth']['basicUsername'], 'ann');

    expect(split.secrets.values, containsAll([
      'Bearer $_token',
      'key-1234567890',
      'Bearer response-secret',
      'session=abc123def456',
      'plain-looking-value',
      'hunter2',
      'orders-bearer-token',
      'pw-archive',
    ]));
    expect(split.secrets.length, 8);
    for (final secret in split.secrets.values) {
      expect(jsonEncode(split.publicDoc), isNot(contains(secret)), reason: 'a secret is left in the public file');
    }
  });

  test('putting the secrets back gives the original document, also after the local file was written and read', () {
    final original = _doc();
    final split = SecretSplitter.split(original);
    final local = SecretSplitter.decodeLocal(SecretSplitter.encodeLocal(split.secrets));

    expect(SecretSplitter.merge(split.publicDoc, local), original);
  });

  test('a secret that nobody else changed is not overwritten by merge, and one a teammate set stays theirs', () {
    final split = SecretSplitter.split(_doc());
    final teammate = jsonDecode(jsonEncode(split.publicDoc)) as Map<String, dynamic>;
    (_collection(teammate)['headers'] as List).cast<Map>().firstWhere((h) => h['key'] == 'X-Api-Key')['value'] = 'their-own-key';

    final merged = SecretSplitter.merge(teammate, split.secrets);

    expect(_value(_collection(merged)['headers'] as List, 'X-Api-Key'), 'their-own-key');
    expect(_value(_collection(merged)['headers'] as List, 'Authorization'), 'Bearer $_token');
  });

  test('an unmatched secret: renaming a folder without a uid leaves its secrets in the local file, renaming it back restores them', () {
    final split = SecretSplitter.split(_doc());
    final renamed = jsonDecode(jsonEncode(split.publicDoc)) as Map<String, dynamic>;
    _folder(renamed, 'Archive')['name'] = 'Old';

    final orphans = SecretSplitter.orphans(renamed, split.secrets);

    expect(orphans.values, ['pw-archive'], reason: 'only what belonged to the renamed folder has lost its place');

    _folder(renamed, 'Old')['name'] = 'Archive';
    expect(SecretSplitter.orphans(renamed, split.secrets), isEmpty);
    expect(_folder(SecretSplitter.merge(renamed, split.secrets), 'Archive')['auth']['basicPassword'], 'pw-archive');
  });

  test('with Git uids a rename or a move does not lose a secret: the folder is found by its uid', () {
    final split = SecretSplitter.split(_doc(withUids: true));
    expect(split.secrets.keys.any((k) => k.startsWith('fauth/@c-uid/@f1-uid')), isTrue, reason: split.secrets.keys.join('\n'));
    final renamed = jsonDecode(jsonEncode(split.publicDoc)) as Map<String, dynamic>;
    _folder(renamed, 'Orders')['name'] = 'Sales';

    expect(SecretSplitter.orphans(renamed, split.secrets), isEmpty);
    final merged = SecretSplitter.merge(renamed, split.secrets);
    expect(_folder(merged, 'Sales')['auth']['bearerToken'], 'orders-bearer-token');
    expect(_value(_folder(merged, 'Sales')['variables'] as List, 'tenantKey'), 'plain-looking-value');
  });

  test('keys written before the collection had a uid still find their secrets once it has one', () {
    final before = SecretSplitter.split(_doc());
    final linked = _doc(withUids: true);
    final publicLinked = SecretSplitter.split(linked).publicDoc;

    final merged = SecretSplitter.merge(publicLinked, before.secrets);

    expect(_folder(merged, 'Orders')['auth']['bearerToken'], 'orders-bearer-token');
    expect(_value(_collection(merged)['headers'] as List, 'Authorization'), 'Bearer $_token');
  });

  test('exposed lists a token that sits in a default header whose name gives nothing away', () {
    final doc = _doc();
    (_collection(doc)['headers'] as List).add({'key': 'X-Debug', 'value': _jwt, 'enabled': true});

    final exposed = SecretSplitter.exposed(doc, keepLocal: true);

    expect(exposed, ['Shop › X-Debug header']);
  });

  test('a document with no defaults splits exactly as before', () {
    final plain = jsonDecode(BackupCodec.encode(BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      collections: [const BackupCollection(name: 'Plain', auth: RequestAuth(type: AuthType.bearer, bearerToken: 'only-this'))],
    ))) as Map<String, dynamic>;

    final split = SecretSplitter.split(plain);

    expect(split.secrets.values, ['only-this']);
  });
}
