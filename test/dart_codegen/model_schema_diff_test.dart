// The "regenerate with diff" engine: every kind of change in both directions, nested classes, list elements, rename
// detection, what counts as breaking for a response and for a request, the snapshot format and the migration notes.
// Classes are built by hand where the expectation needs exact control, and by the real model generator where the
// point is that the whole chain (JSON samples to classes to diff) behaves.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/model_schema_diff.dart';

SchemaField f(String json, String type, {bool nullable = false, String? name}) => SchemaField(json, name ?? json, type, nullable);

SchemaSnapshot snap(Map<String, List<SchemaField>> classes, {SchemaRole role = SchemaRole.response, String file = 'user.dart'}) =>
    SchemaSnapshot({file: SchemaScope(role, [for (final e in classes.entries) SchemaClass(e.key, e.value)])});

List<SchemaChange> changes(SchemaSnapshot before, SchemaSnapshot after) => SchemaDiffer.diff(before, after).changes;

SchemaSnapshot modelSnapshot(List<String> samples, {String root = 'User', SchemaRole role = SchemaRole.response}) =>
    SchemaSnapshot.ofModel('${root.toLowerCase()}.dart', const DartModelGenerator().generate(samples, rootName: root), role: role);

void main() {
  group('classes', () {
    final base = snap({'User': [f('id', 'int')]});
    final withAddress = snap({'User': [f('id', 'int')], 'Address': [f('city', 'String')]});

    test('a new class is not breaking', () {
      final c = changes(base, withAddress).single;
      expect(c.kind, SchemaChangeKind.classAdded);
      expect(c.className, 'Address');
      expect(c.breaking, isFalse);
    });

    test('a class that is gone is breaking', () {
      final c = changes(withAddress, base).single;
      expect(c.kind, SchemaChangeKind.classRemoved);
      expect(c.className, 'Address');
      expect(c.breaking, isTrue);
      expect(c.summary, contains('no longer exists'));
    });

    test('a whole file added or removed is its classes added or removed', () {
      final other = snap({'Order': [f('id', 'int')]}, file: 'order.dart');
      final both = SchemaSnapshot({...base.scopes, ...other.scopes});
      expect(changes(base, both).map((c) => (c.kind, c.className)), [(SchemaChangeKind.classAdded, 'Order')]);
      expect(changes(both, base).map((c) => (c.kind, c.className)), [(SchemaChangeKind.classRemoved, 'Order')]);
    });

    test('identical snapshots have no changes', () {
      expect(SchemaDiffer.diff(withAddress, withAddress).isEmpty, isTrue);
      expect(SchemaDiffer.diff(withAddress, withAddress).migrationNotes(), 'The generated models are unchanged.');
    });
  });

  group('fields added and removed', () {
    final plain = {'User': [f('id', 'int')]};
    final withNote = {'User': [f('id', 'int'), f('note', 'String', nullable: true)]};
    final withRequired = {'User': [f('id', 'int'), f('age', 'int')]};

    for (final role in SchemaRole.values) {
      test('an optional field added is safe and one removed is breaking (${role.name})', () {
        final added = changes(snap(plain, role: role), snap(withNote, role: role)).single;
        expect(added.kind, SchemaChangeKind.fieldAdded);
        expect(added.field, 'note');
        expect(added.after, 'String?');
        expect(added.breaking, isFalse);
        final removed = changes(snap(withNote, role: role), snap(plain, role: role)).single;
        expect(removed.kind, SchemaChangeKind.fieldRemoved);
        expect(removed.before, 'String?');
        expect(removed.breaking, isTrue);
      });
    }

    test('a required field added breaks the code that builds the class, not the code that reads it', () {
      final response = changes(snap(plain), snap(withRequired)).single;
      expect(response.kind, SchemaChangeKind.fieldAdded);
      expect(response.breaking, isFalse);
      final request = changes(snap(plain, role: SchemaRole.request), snap(withRequired, role: SchemaRole.request)).single;
      expect(request.breaking, isTrue);
      expect(request.advice, contains('Add `age:`'));
    });

    test('a required field removed is breaking for both', () {
      for (final role in SchemaRole.values) {
        final c = changes(snap(withRequired, role: role), snap(plain, role: role)).single;
        expect(c.kind, SchemaChangeKind.fieldRemoved);
        expect(c.breaking, isTrue);
      }
    });
  });

  group('renames', () {
    test('one field gone and one new with the same type is a suspected rename, both ways', () {
      final a = snap({'User': [f('id', 'int'), f('email', 'String')]});
      final b = snap({'User': [f('id', 'int'), f('mail', 'String')]});
      final forward = changes(a, b).single;
      expect(forward.kind, SchemaChangeKind.fieldRenamed);
      expect((forward.oldField, forward.field), ('email', 'mail'));
      expect(forward.breaking, isTrue);
      expect(forward.summary, contains('looks renamed'));
      final back = changes(b, a).single;
      expect(back.kind, SchemaChangeKind.fieldRenamed);
      expect((back.oldField, back.field), ('mail', 'email'));
    });

    test('a different type is a removal and an addition', () {
      final a = snap({'User': [f('count', 'int')]});
      final b = snap({'User': [f('title', 'String')]});
      expect(changes(a, b).map((c) => c.kind).toSet(), {SchemaChangeKind.fieldRemoved, SchemaChangeKind.fieldAdded});
    });

    test('with several candidates the most alike names are paired', () {
      final a = snap({'User': [f('first_name', 'String'), f('last_name', 'String')]});
      final b = snap({'User': [f('given_name', 'String'), f('family_name', 'String')]});
      final renames = {for (final c in changes(a, b)) if (c.kind == SchemaChangeKind.fieldRenamed) c.oldField: c.field};
      expect(renames, {'first_name': 'given_name', 'last_name': 'family_name'});
    });

    test('unrelated names are not paired when there is more than one candidate', () {
      final a = snap({'User': [f('alpha', 'String'), f('beta', 'String')]});
      final b = snap({'User': [f('zzz', 'String'), f('qqq', 'String')]});
      expect(changes(a, b).map((c) => c.kind).toSet(), {SchemaChangeKind.fieldRemoved, SchemaChangeKind.fieldAdded});
    });

    test('a rename that also changes nullability reports both', () {
      final a = snap({'User': [f('email', 'String')]});
      final b = snap({'User': [f('mail', 'String', nullable: true)]});
      expect(changes(a, b).map((c) => c.kind).toSet(), {SchemaChangeKind.fieldRenamed, SchemaChangeKind.nullabilityChanged});
    });

    test('renames are looked for inside one class only', () {
      final a = snap({'User': [f('email', 'String')], 'Order': [f('id', 'int')]});
      final b = snap({'User': [f('id', 'int')], 'Order': [f('mail', 'String')]});
      expect(changes(a, b).where((c) => c.kind == SchemaChangeKind.fieldRenamed), isEmpty);
    });
  });

  group('types', () {
    void expectChange(String from, String to, {String? mentions}) {
      final c = changes(snap({'User': [f('x', from)]}), snap({'User': [f('x', to)]})).single;
      expect(c.kind, SchemaChangeKind.typeChanged, reason: '$from to $to');
      expect((c.before, c.after), (from, to));
      expect(c.breaking, isTrue);
      if (mentions != null) expect(c.advice, contains(mentions));
    }

    test('int and double, both ways', () {
      expectChange('int', 'double');
      expectChange('double', 'int');
    });

    test('a scalar becoming a list and back', () {
      expectChange('String', 'List<String>');
      expectChange('List<String>', 'String');
    });

    test('the element type of a list', () {
      expectChange('List<String>', 'List<int>');
      expectChange('List<int>', 'List<String>');
      expectChange('List<Item>', 'List<Line>');
    });

    test('list items that become nullable, and the reverse, are said in words', () {
      expectChange('List<String>', 'List<String?>', mentions: 'can now be null');
      expectChange('List<String?>', 'List<String>', mentions: 'never null');
    });

    test('a map value type', () {
      expectChange('Map<String, int>', 'Map<String, String>');
    });
  });

  group('nullability', () {
    final optional = {'User': [f('email', 'String', nullable: true)]};
    final required = {'User': [f('email', 'String')]};

    test('response: becoming nullable breaks the readers, becoming required does not', () {
      final toNullable = changes(snap(required), snap(optional)).single;
      expect(toNullable.kind, SchemaChangeKind.nullabilityChanged);
      expect((toNullable.before, toNullable.after), ('String', 'String?'));
      expect(toNullable.breaking, isTrue);
      expect(toNullable.advice, contains('Handle null'));
      final toRequired = changes(snap(optional), snap(required)).single;
      expect((toRequired.before, toRequired.after), ('String?', 'String'));
      expect(toRequired.breaking, isFalse);
    });

    test('request: becoming required breaks the builders, becoming nullable does not', () {
      final toRequired = changes(snap(optional, role: SchemaRole.request), snap(required, role: SchemaRole.request)).single;
      expect(toRequired.breaking, isTrue);
      expect(toRequired.advice, contains('Add `email:`'));
      final toNullable = changes(snap(required, role: SchemaRole.request), snap(optional, role: SchemaRole.request)).single;
      expect(toNullable.breaking, isFalse);
    });

    test('a type and a nullability change on one field are two changes', () {
      final c = changes(snap({'User': [f('x', 'int')]}), snap({'User': [f('x', 'String', nullable: true)]}));
      expect(c.map((e) => e.kind), [SchemaChangeKind.typeChanged, SchemaChangeKind.nullabilityChanged]);
    });
  });

  group('from real JSON samples', () {
    test('a field that appears inside a nested object is reported under the nested class', () {
      final before = modelSnapshot(['{"id":1,"address":{"city":"Oslo"}}']);
      final after = modelSnapshot(['{"id":1,"address":{"city":"Oslo","zip":"0150"}}']);
      final c = changes(before, after).single;
      expect(c.className, 'Address');
      expect(c.kind, SchemaChangeKind.fieldAdded);
      expect((c.field, c.after), ('zip', 'String'));
      expect(c.breaking, isFalse, reason: 'a response gained a field');
    });

    test('list elements: a retyped list of scalars and a list of objects that gained a field', () {
      final before = modelSnapshot(['{"tags":["a"],"items":[{"sku":"a"}]}']);
      final after = modelSnapshot(['{"tags":[1],"items":[{"sku":"a","qty":2}]}']);
      final byClass = SchemaDiffer.diff(before, after).byClass;
      expect(byClass.keys, containsAll(['User', 'Item']));
      final tags = byClass['User']!.single;
      expect((tags.kind, tags.before, tags.after), (SchemaChangeKind.typeChanged, 'List<String>', 'List<int>'));
      final qty = byClass['Item']!.single;
      expect((qty.kind, qty.field, qty.after), (SchemaChangeKind.fieldAdded, 'qty', 'int'));
    });

    test('a null inside a list makes its items nullable', () {
      final c = changes(modelSnapshot(['{"tags":["a"]}']), modelSnapshot(['{"tags":["a",null]}'])).single;
      expect((c.before, c.after), ('List<String>', 'List<String?>'));
      expect(c.advice, contains('can now be null'));
    });

    test('a second sample that lacks a field makes it optional', () {
      final before = modelSnapshot(['{"id":1,"email":"a"}']);
      final after = modelSnapshot(['{"id":1,"email":"a"}', '{"id":2}']);
      final c = changes(before, after).single;
      expect(c.kind, SchemaChangeKind.nullabilityChanged);
      expect(c.className, 'User');
      expect(c.breaking, isTrue);
      final asRequest = changes(
        modelSnapshot(['{"id":1,"email":"a"}'], role: SchemaRole.request),
        modelSnapshot(['{"id":1,"email":"a"}', '{"id":2}'], role: SchemaRole.request),
      ).single;
      expect(asRequest.breaking, isFalse, reason: 'optional is easier for the code that builds a request');
    });

    test('a field renamed between two responses of the endpoint', () {
      final c = changes(modelSnapshot(['{"id":1,"user_name":"a"}']), modelSnapshot(['{"id":1,"username":"a"}'])).single;
      expect(c.kind, SchemaChangeKind.fieldRenamed);
      expect((c.oldField, c.field), ('userName', 'username'));
    });
  });

  group('snapshot', () {
    test('keeps names, types and nullability through its text form', () {
      final original = SchemaSnapshot({
        'a.dart': SchemaScope(SchemaRole.request, [SchemaClass('A', [f('x_y', 'List<int>', nullable: true, name: 'xY')])]),
        'b.dart': SchemaScope(SchemaRole.response, [SchemaClass('B', const [])]),
      });
      final restored = SchemaSnapshot.tryParse(original.toText())!;
      expect(restored.scopes.keys, ['a.dart', 'b.dart']);
      expect(restored.scopes['a.dart']!.role, SchemaRole.request);
      final field = restored.scopes['a.dart']!.classes.single.fields.single;
      expect((field.json, field.name, field.type, field.nullable), ('x_y', 'xY', 'List<int>', true));
      expect(SchemaDiffer.diff(original, restored).isEmpty, isTrue);
    });

    test('anything that is not a snapshot of this version is no baseline', () {
      expect(SchemaSnapshot.tryParse(null), isNull);
      expect(SchemaSnapshot.tryParse(''), isNull);
      expect(SchemaSnapshot.tryParse('not json'), isNull);
      expect(SchemaSnapshot.tryParse('[]'), isNull);
      expect(SchemaSnapshot.tryParse(jsonEncode({'v': 99, 's': {}})), isNull);
      expect(SchemaSnapshot.tryParse(jsonEncode({'v': 1, 's': {'a.dart': {'c': [{'n': 'A', 'f': [['x']]}]}}})), isNull);
    });

    test('holds the shape only: no value of a sample is in it', () {
      const secret = 'sk_live_abcdefghijklmnopqrstuv';
      final text = modelSnapshot(['{"id":1,"api_token":"$secret","pin":4321,"name":"Ann Smith"}']).toText();
      expect(text, isNot(contains(secret)));
      expect(text, isNot(contains('4321')));
      expect(text, isNot(contains('Ann Smith')));
      expect(text, contains('api_token'));
    });
  });

  group('migration notes', () {
    test('list the breaking changes first, per class, with what to do', () {
      final before = snap({
        'User': [f('id', 'int'), f('coupon', 'String'), f('total', 'int')],
        'Address': [f('city', 'String')],
      });
      final after = snap({
        'User': [f('id', 'int'), f('total', 'double'), f('nickname', 'int', nullable: true)],
      });
      final diff = SchemaDiffer.diff(before, after);
      expect(diff.breaking.length, 3, reason: 'coupon removed, total retyped, Address removed');
      expect(diff.nonBreaking.length, 1);
      final notes = diff.migrationNotes();
      expect(notes, startsWith('Migration notes: 4 changes (3 breaking, 1 non-breaking)'));
      expect(notes.indexOf('Breaking:'), lessThan(notes.indexOf('Non-breaking:')));
      // The classes come in the order their first change was found: Address (gone), then User.
      expect(notes, contains('    - Field coupon (String) was removed.'));
      expect(notes, contains('Delete every read or write of `.coupon`'));
      expect(notes, contains('  User\n    - Field total changed from int to double.'));
      expect(notes, contains('  Address\n    - Class Address no longer exists'));
      expect(notes, contains('New field nickname (int?), optional.'));
    });
  });
}
