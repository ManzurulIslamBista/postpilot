import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/defaults_chain.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/services/defaults_resolver.dart';
import 'package:postpilot/features/defaults/domain/services/header_inheritance.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';

KeyValueItem _h(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

List<String> _pairs(List<KeyValueItem> rows) => [for (final r in rows) '${r.key}=${r.value}'];

FolderEntity _folder(int id, String name, int? parent) =>
    FolderEntity(id: id, collectionId: 1, parentFolderId: parent, name: name);

void main() {
  group('HeaderInheritance.merge', () {
    test('lists the levels outermost first, keeping the order inside each', () {
      final merged = HeaderInheritance.merge([
        [_h('A', '1'), _h('B', '2')],
        [_h('C', '3')],
        [_h('D', '4')],
      ]);
      expect(_pairs(merged), ['A=1', 'B=2', 'C=3', 'D=4']);
    });

    test('a more specific level replaces a header of the same name whatever its letter case', () {
      final merged = HeaderInheritance.merge([
        [_h('X-Api-Version', '1'), _h('Accept', 'text/html')],
        [_h('x-api-version', '2')],
      ]);
      expect(_pairs(merged), ['Accept=text/html', 'x-api-version=2']);
    });

    test('a disabled row switches off the header of that name from every level above', () {
      final merged = HeaderInheritance.merge([
        [_h('Accept-Language', 'en'), _h('X-Tenant', 'acme')],
        [_h('ACCEPT-LANGUAGE', 'ignored', enabled: false)],
      ]);
      expect(_pairs(merged), ['X-Tenant=acme']);
    });

    test('a disabled row with nothing above it to switch off sends nothing', () {
      expect(HeaderInheritance.merge([
        [_h('X-Foo', '1', enabled: false)],
      ]), isEmpty);
    });

    test('a level inside the one that switched a header off can set it again', () {
      final merged = HeaderInheritance.merge([
        [_h('X', '1')],
        [_h('X', '', enabled: false)],
        [_h('X', '3')],
      ]);
      expect(_pairs(merged), ['X=3']);
    });

    test('a level that repeats a name keeps every enabled row of it', () {
      final merged = HeaderInheritance.merge([
        [_h('Cookie', 'a=1')],
        [_h('Cookie', 'b=2'), _h('Cookie', 'c=3'), _h('Cookie', 'off', enabled: false)],
      ]);
      expect(_pairs(merged), ['Cookie=b=2', 'Cookie=c=3']);
    });

    test('names are compared as nameOf gives them, so a variable in a name can match', () {
      final merged = HeaderInheritance.merge(
        [
          [_h('X-Tenant', 'acme')],
          [_h('{{header}}', 'globex')],
        ],
        nameOf: (key) => key == '{{header}}' ? 'x-tenant' : key,
      );
      expect(_pairs(merged), ['{{header}}=globex']);
    });

    test('rows without a name are skipped', () {
      expect(_pairs(HeaderInheritance.merge([
        [_h('', 'orphan'), _h('A', '1')],
      ])), ['A=1']);
    });

    test('mergeWithLevels says which level each surviving row came from', () {
      final rows = HeaderInheritance.mergeWithLevels([
        [_h('A', '1'), _h('B', '2')],
        [_h('B', '3')],
      ]);
      expect([for (final r in rows) (r.level, r.item.key, r.item.value)], [(0, 'A', '1'), (1, 'B', '3')]);
    });
  });

  group('HeaderInheritance.materialize', () {
    test('writes the inherited rows ahead of the request\'s own and drops the ones it names', () {
      final rows = HeaderInheritance.materialize(
        [_h('X-Tenant', 'acme'), _h('Accept', 'a/b')],
        [_h('accept', 'c/d'), _h('X-Own', '1')],
      );
      expect(_pairs(rows), ['X-Tenant=acme', 'accept=c/d', 'X-Own=1']);
    });

    test('a disabled own row still removes the inherited header and stays in the list', () {
      final rows = HeaderInheritance.materialize([_h('X-Tenant', 'acme')], [_h('X-TENANT', '', enabled: false)]);
      expect(rows.map((r) => (r.key, r.enabled)).toList(), [('X-TENANT', false)]);
    });
  });

  group('DefaultsResolver', () {
    // Shop > Orders > Archive > Old: three folders deep.
    final tree = DefaultsTree(
      collectionName: 'Shop',
      collectionId: 1,
      collection: LevelDefaults(
        headers: [_h('X-Tenant', 'acme'), _h('Accept-Language', 'en')],
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'shop-token'),
        assertions: [AssertionEntity(type: AssertionType.statusIn2xx)],
      ),
      folders: [
        _folder(10, 'Orders', null),
        _folder(11, 'Archive', 10),
        _folder(12, 'Old', 11),
        _folder(20, 'Users', null),
      ],
      folderDefaults: {
        10: LevelDefaults(
          headers: [_h('X-Api-Version', '2'), _h('accept-language', 'bn')],
          variables: [
            DefaultVariable(key: 'region', value: 'eu'),
            DefaultVariable(key: 'pageSize', value: '10'),
          ],
          extractors: [ExtractorEntity(path: r'$.id', variableKey: 'orderId')],
        ),
        11: LevelDefaults(
          headers: [_h('X-Tenant', '', enabled: false)],
          variables: [
            DefaultVariable(key: 'region', value: 'us'),
            DefaultVariable(key: 'apiSecret', value: 's3', isSecret: true),
          ],
          auth: const RequestAuth(type: AuthType.basic, basicUsername: 'ann', basicPassword: 'pw'),
        ),
        12: LevelDefaults(variables: [DefaultVariable(key: 'region', value: 'zz', enabled: false)]),
      },
    );

    test('three folders deep: headers override and switch off across levels, in level order', () {
      final inherited = DefaultsResolver.resolve(tree.chainFor(12));
      expect([for (final h in inherited.headers) '${h.item.key}=${h.item.value} (${h.origin.label})'], [
        'X-Api-Version=2 (folder "Orders")',
        'accept-language=bn (folder "Orders")',
      ]);
    });

    test('the nearest folder that sets an auth wins, and a folder set to inherit does not hide the one above', () {
      final inherited = DefaultsResolver.resolve(tree.chainFor(12));
      expect(inherited.auth?.type, AuthType.basic);
      expect(inherited.authOrigin?.label, 'folder "Archive"');

      final orders = DefaultsResolver.resolve(tree.chainFor(10));
      expect(orders.auth?.type, AuthType.bearer, reason: 'Orders sets none, so the collection\'s applies');
      expect(orders.authOrigin?.label, 'collection "Shop"');
    });

    test('variables: the innermost folder comes first, a disabled one is not visible', () {
      final inherited = DefaultsResolver.resolve(tree.chainFor(12));
      expect(inherited.variableScopes, [
        <String, String>{},
        {'region': 'us', 'apiSecret': 's3'},
        {'region': 'eu', 'pageSize': '10'},
      ]);
      expect([for (final v in inherited.variables) '${v.origin.name}:${v.variable.key}'], [
        'Orders:region',
        'Orders:pageSize',
        'Archive:region',
        'Archive:apiSecret',
      ]);
    });

    test('tests: the collection\'s first, then each folder\'s from the outermost, only levels that have any', () {
      final inherited = DefaultsResolver.resolve(tree.chainFor(12));
      expect([for (final t in inherited.tests) t.origin.label], ['collection "Shop"', 'folder "Orders"']);
      expect(inherited.tests.first.assertions.single.type, AssertionType.statusIn2xx);
      expect(inherited.tests.last.extractors.single.variableKey, 'orderId');
    });

    test('a request at the top level inherits the collection alone', () {
      final inherited = DefaultsResolver.resolve(tree.chainFor(null));
      expect([for (final h in inherited.headers) h.item.key], ['X-Tenant', 'Accept-Language']);
      expect(inherited.auth?.bearerToken, 'shop-token');
      expect(inherited.variableScopes, isEmpty);
    });

    test('a folder in another branch inherits none of Orders', () {
      final inherited = DefaultsResolver.resolve(tree.chainFor(20));
      expect([for (final h in inherited.headers) h.item.key], ['X-Tenant', 'Accept-Language']);
      expect(inherited.variableScopes, [<String, String>{}]);
    });

    test('an explicit No Auth on a folder ends the search, below it and not above', () {
      final noAuth = DefaultsTree(
        collectionName: 'Shop',
        collection: const LevelDefaults(auth: RequestAuth(type: AuthType.bearer, bearerToken: 't')),
        folders: [_folder(1, 'Public', null), _folder(2, 'Inner', 1)],
        folderDefaults: {1: const LevelDefaults(auth: RequestAuth(type: AuthType.none))},
      );
      final inner = DefaultsResolver.resolve(noAuth.chainFor(2));
      expect(inner.auth?.type, AuthType.none);
      expect(inner.authOrigin?.name, 'Public');
      expect(DefaultsResolver.resolve(noAuth.chainFor(null)).auth?.type, AuthType.bearer);
    });

    test('a folder set to inherit under a folder with bearer takes the bearer', () {
      final nested = DefaultsTree(
        collectionName: 'Shop',
        folders: [_folder(1, 'Parent', null), _folder(2, 'Child', 1)],
        folderDefaults: {
          1: const LevelDefaults(auth: RequestAuth(type: AuthType.bearer, bearerToken: 'parent-token')),
          2: LevelDefaults(headers: [_h('X-Only-Child', '1')]),
        },
      );
      final child = DefaultsResolver.resolve(nested.chainFor(2));
      expect(child.auth?.bearerToken, 'parent-token');
      expect(child.authOrigin?.label, 'folder "Parent"');
    });

    test('nothing set anywhere inherits nothing', () {
      final empty = DefaultsResolver.resolve(const DefaultsTree(collectionName: 'Empty').chainFor(null));
      expect(empty.headers, isEmpty);
      expect(empty.auth, isNull);
      expect(empty.tests, isEmpty);
      expect(empty.variableScopes, isEmpty);
    });
  });

  group('DefaultsTree', () {
    test('a folder that is not in the tree ends the walk at the collection', () {
      const tree = DefaultsTree(collectionName: 'C');
      expect(tree.chainFor(99).scopes.map((s) => s.origin.label), ['collection "C"']);
    });

    test('a parent loop in damaged data does not hang', () {
      final tree = DefaultsTree(collectionName: 'C', folders: [_folder(1, 'A', 2), _folder(2, 'B', 1)]);
      expect(tree.chainFor(1).scopes.length, lessThanOrEqualTo(3));
    });

    test('chainAbove leaves the folder itself out', () {
      final tree = DefaultsTree(collectionName: 'C', folders: [_folder(1, 'A', null), _folder(2, 'B', 1)]);
      expect(tree.chainAbove(2).scopes.map((s) => s.origin.label), ['collection "C"', 'folder "A"']);
      expect(tree.chainAbove(1).scopes.map((s) => s.origin.label), ['collection "C"']);
      expect(tree.chainAbove(null).scopes.map((s) => s.origin.label), ['collection "C"']);
    });
  });
}
