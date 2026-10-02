import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/graphql/domain/services/graphql_query_builder.dart';
import 'package:postpilot/features/graphql/domain/services/graphql_schema.dart';

Map<String, dynamic> _ref(String kind, String? name, [Map<String, dynamic>? of]) => {'kind': kind, 'name': name, 'ofType': of};

Map<String, dynamic> _scalar(String n) => _ref('SCALAR', n);
Map<String, dynamic> _nonNull(Map<String, dynamic> t) => _ref('NON_NULL', null, t);
Map<String, dynamic> _list(Map<String, dynamic> t) => _ref('LIST', null, t);

Map<String, dynamic> _field(String name, Map<String, dynamic> type, {List<Map<String, dynamic>> args = const [], bool deprecated = false}) =>
    {'name': name, 'description': '$name docs', 'isDeprecated': deprecated, 'args': args, 'type': type};

Map<String, dynamic> _arg(String name, Map<String, dynamic> type, {String? def}) => {'name': name, 'description': '', 'defaultValue': def, 'type': type};

String _schemaJson() => jsonEncode({
      'data': {
        '__schema': {
          'queryType': {'name': 'Query'},
          'mutationType': {'name': 'Mutation'},
          'subscriptionType': null,
          'types': [
            {
              'kind': 'OBJECT',
              'name': 'Query',
              'fields': [
                _field('user', _ref('OBJECT', 'User'), args: [_arg('id', _nonNull(_scalar('ID')))]),
                _field('users', _nonNull(_list(_nonNull(_ref('OBJECT', 'User')))), args: [_arg('first', _scalar('Int'), def: '10')]),
                _field('legacy', _scalar('String'), deprecated: true),
              ],
            },
            {
              'kind': 'OBJECT',
              'name': 'Mutation',
              'fields': [
                _field('createUser', _ref('OBJECT', 'User'), args: [_arg('input', _nonNull(_ref('INPUT_OBJECT', 'NewUser')))]),
              ],
            },
            {
              'kind': 'OBJECT',
              'name': 'User',
              'description': 'A person',
              'interfaces': [_ref('INTERFACE', 'Node')],
              'fields': [
                _field('id', _nonNull(_scalar('ID'))),
                _field('name', _scalar('String')),
                _field('role', _ref('ENUM', 'Role')),
                _field('posts', _list(_ref('OBJECT', 'Post'))),
                _field('friends', _list(_ref('OBJECT', 'User'))),
                _field('secret', _scalar('String'), args: [_arg('key', _nonNull(_scalar('String')))]),
              ],
            },
            {
              'kind': 'OBJECT',
              'name': 'Post',
              'fields': [
                _field('id', _nonNull(_scalar('ID'))),
                _field('title', _scalar('String')),
                _field('author', _ref('OBJECT', 'User')),
              ],
            },
            {
              'kind': 'INPUT_OBJECT',
              'name': 'NewUser',
              'inputFields': [
                _arg('name', _nonNull(_scalar('String'))),
                _arg('age', _scalar('Int')),
                _arg('role', _ref('ENUM', 'Role')),
              ],
            },
            {
              'kind': 'ENUM',
              'name': 'Role',
              'enumValues': [
                {'name': 'ADMIN', 'description': '', 'isDeprecated': false},
                {'name': 'USER', 'description': '', 'isDeprecated': false},
              ],
            },
            {'kind': 'INTERFACE', 'name': 'Node', 'fields': [_field('id', _nonNull(_scalar('ID')))], 'possibleTypes': [_ref('OBJECT', 'User')]},
            {'kind': 'SCALAR', 'name': 'String'},
            {'kind': 'SCALAR', 'name': '__Hidden'},
          ],
        },
      },
    });

void main() {
  group('GqlSchema.parse', () {
    test('reads root types, fields, args, wrappers and enums', () {
      final s = GqlSchema.parse(_schemaJson())!;
      expect(s.queryType, 'Query');
      expect(s.mutationType, 'Mutation');
      expect(s.subscriptionType, isNull);
      final users = s.rootFields('query').firstWhere((f) => f.name == 'users');
      expect(users.type.toString(), '[User!]!');
      expect(users.type.namedType, 'User');
      expect(users.type.isList, isTrue);
      expect(users.args.single.defaultValue, '10');
      expect(users.args.single.isRequired, isFalse);
      expect(s.rootFields('query').first.args.single.isRequired, isTrue);
      expect(s.type('Role')!.enumValues.map((e) => e.name), ['ADMIN', 'USER']);
      expect(s.type('User')!.interfaces, ['Node']);
      expect(s.type('Node')!.possibleTypes, ['User']);
    });

    test('lists the types a person would browse', () {
      final names = GqlSchema.parse(_schemaJson())!.userTypes.map((t) => t.name);
      expect(names, containsAll(['Query', 'User', 'Role', 'NewUser']));
      expect(names, isNot(contains('String')));
      expect(names, isNot(contains('__Hidden')));
    });

    test('accepts the bare __schema object and rejects everything else', () {
      final inner = jsonEncode((jsonDecode(_schemaJson()) as Map)['data']);
      expect(GqlSchema.parse(inner), isNotNull);
      expect(GqlSchema.parse('{"data": {"user": 1}}'), isNull);
      expect(GqlSchema.parse('nope'), isNull);
      expect(GqlSchema.parse('[]'), isNull);
    });
  });

  group('GqlQueryBuilder', () {
    final schema = GqlSchema.parse(_schemaJson())!;

    test('arguments become variables; scalars and nested objects are selected', () {
      final field = schema.rootFields('query').firstWhere((f) => f.name == 'user');
      final op = GqlQueryBuilder.forField(schema, 'query', field);
      expect(op.query, startsWith(r'query User($id: ID!) {'));
      expect(op.query, contains(r'user(id: $id) {'));
      expect(op.query, contains('    id\n'));
      expect(op.query, contains('    name\n'));
      expect(op.query, contains('role'), reason: 'enums are scalars for selection');
      expect(op.query, contains('posts {'));
      expect(op.query, contains('title'));
      expect(op.query, isNot(contains('secret')), reason: 'a field with a required argument is skipped');
      expect(op.query, isNot(contains('friends {\n        friends')), reason: 'a type never nests inside itself');
      expect(jsonDecode(op.variables), {'id': ''});
    });

    test('optional args with defaults still become variables; lists of non-null work', () {
      final field = schema.rootFields('query').firstWhere((f) => f.name == 'users');
      final op = GqlQueryBuilder.forField(schema, 'query', field);
      expect(op.query, startsWith(r'query Users($first: Int) {'));
      expect(jsonDecode(op.variables), {'first': 0});
    });

    test('mutations with input objects get a sample input', () {
      final field = schema.rootFields('mutation').single;
      final op = GqlQueryBuilder.forField(schema, 'mutation', field);
      expect(op.query, startsWith(r'mutation CreateUser($input: NewUser!) {'));
      expect(jsonDecode(op.variables), {
        'input': {'name': '', 'age': 0, 'role': 'ADMIN'},
      });
    });

    test('braces balance in every generated operation', () {
      for (final op in ['query', 'mutation']) {
        for (final f in schema.rootFields(op)) {
          final q = GqlQueryBuilder.forField(schema, op, f).query;
          expect('{'.allMatches(q).length, '}'.allMatches(q).length, reason: q);
        }
      }
    });

    test('a field returning a scalar has no selection set', () {
      final op = GqlQueryBuilder.forField(schema, 'query', schema.rootFields('query').firstWhere((f) => f.name == 'legacy'));
      expect(op.query, 'query Legacy {\n  legacy\n}');
    });
  });
}
