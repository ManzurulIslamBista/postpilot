import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/scripting/domain/evaluator/json_path_resolver.dart';
import 'package:postpilot/features/test_suggestions/domain/services/field_path.dart';

void main() {
  group('FieldPath', () {
    test('plain keys join with dots, other keys are bracket-quoted', () {
      expect(FieldPath.child('', 'data'), 'data');
      expect(FieldPath.child('data', 'items'), 'data.items');
      expect(FieldPath.child('data', 'x-id'), 'data.x-id');
      expect(FieldPath.child('data', 'a.b'), 'data["a.b"]');
      expect(FieldPath.child('', 'first name'), '["first name"]');
      expect(FieldPath.child('', '123'), '["123"]');
      // A key with a double quote is written with single quotes; one with both kinds has no path.
      expect(FieldPath.child('a', 'say "hi"'), "a['say \"hi\"']");
      expect(FieldPath.child('a', 'it\'s "x"'), isNull);
      expect(FieldPath.child('', r'$'), isNull);
      expect(FieldPath.child('', ''), isNull);
    });

    test('steps and join are inverses, with the element marker for arrays', () {
      const paths = ['', 'a', 'a.b', 'a[]', 'a[].b', 'a[].b[].c', '["x.y"].z', 'a["k k"][]'];
      for (final path in paths) {
        expect(FieldPath.join(FieldPath.steps(path)), path, reason: path);
      }
      expect(FieldPath.steps('data.items[].id'), ['data', 'items', FieldPath.elementStep, 'id']);
      expect(FieldPath.steps('["a.b"].c'), ['a.b', 'c']);
    });

    test('a column path becomes a path the resolver reads with an index', () {
      final json = {
        'items': [
          {'id': 'one'},
          {'id': 'two'},
        ],
      };
      final path = FieldPath.index('items[].id', 'items', 1);
      expect(path, 'items[1].id');
      expect(JsonPathResolver.resolve(json, path), 'two');
      expect(FieldPath.index('other[].id', 'items', 1), 'other[].id');
    });

    test('crossesArray, depth, lastKey', () {
      expect(FieldPath.crossesArray('a.b'), isFalse);
      expect(FieldPath.crossesArray('a[].b'), isTrue);
      expect(FieldPath.depth(''), 0);
      expect(FieldPath.depth('a.b[].c'), 4);
      expect(FieldPath.lastKey('a.b.created_at'), 'created_at');
      expect(FieldPath.lastKey('a[]'), '');
      expect(FieldPath.lastKey(''), '');
    });

    test('display reads as a sentence', () {
      expect(FieldPath.display(''), 'body');
      expect(FieldPath.display('data.items[].id'), 'body.data.items[*].id');
      expect(FieldPath.display('[].id'), 'body[*].id');
    });

    test('isUnder follows the path structure, not the text', () {
      expect(FieldPath.isUnder('a.b', 'a'), isTrue);
      expect(FieldPath.isUnder('a[]', 'a'), isTrue);
      expect(FieldPath.isUnder('a', 'a'), isTrue);
      expect(FieldPath.isUnder('ab', 'a'), isFalse);
      expect(FieldPath.isUnder('a2.b', 'a'), isFalse);
      expect(FieldPath.isUnder('anything', ''), isTrue);
    });

    test('normalize drops a leading dollar and blanks', () {
      expect(FieldPath.normalize(r' $.data.id '), 'data.id');
      expect(FieldPath.normalize(r'$'), '');
      expect(FieldPath.normalize(r'$[0].id'), '[0].id');
      expect(FieldPath.normalize('data.id'), 'data.id');
    });
  });
}
