import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_names.dart';

void main() {
  const gen = DartModelGenerator();

  group('DartNames', () {
    test('converts to pascal, camel and snake', () {
      expect(DartNames.pascal('res.partner'), 'ResPartner');
      expect(DartNames.camel('created_at'), 'createdAt');
      expect(DartNames.camel('class'), 'classValue');
      expect(DartNames.camel('2fa_code'), 'n2faCode');
      expect(DartNames.snake('UserProfile'), 'user_profile');
    });

    test('singularises list names', () {
      expect(DartNames.singular('orders'), 'order');
      expect(DartNames.singular('categories'), 'category');
      expect(DartNames.singular('status'), 'status');
    });

    test('quotes awkward strings', () {
      expect(DartNames.quote("it's \$5"), r"'it\'s \$5'");
    });
  });

  group('DartModelGenerator', () {
    test('merges samples: missing and null make nullable, int+double widen', () {
      final r = gen.generate([
        '{"id":1,"price":9.5,"note":null,"tags":["a"]}',
        '{"id":2,"price":10,"extra":true,"tags":[]}',
      ], rootName: 'item');
      expect(r.classCount, 1);
      expect(r.code, contains('final int id;'));
      expect(r.code, contains('final double price;'));
      expect(r.code, contains('final bool? extra;'));
      expect(r.code, contains('final List<String> tags;'));
      expect(r.code, contains("final dynamic note;"));
    });

    test('nested objects and lists get their own classes', () {
      final r = gen.generate([
        '{"user":{"name":"A"},"orders":[{"id":1},{"id":2,"note":"x"}]}',
      ], rootName: 'root');
      expect(r.classCount, 3);
      expect(r.code, contains('class Root'));
      expect(r.code, contains('class User'));
      expect(r.code, contains('class Order'));
      expect(r.code, contains('final String? note;'));
      expect(r.code, contains("User.fromJson(json['user'] as Map<String, dynamic>)"));
    });

    test('detects ISO dates and round-trips them', () {
      final r = gen.generate(['{"created_at":"2026-10-02T10:00:00Z"}']);
      expect(r.code, contains('final DateTime createdAt;'));
      expect(r.code, contains("DateTime.parse(json['created_at'] as String)"));
      expect(r.code, contains("'created_at': createdAt.toIso8601String()"));
      final off = gen.generate(['{"created_at":"2026-10-02T10:00:00Z"}'], options: const DartModelOptions(detectDates: false));
      expect(off.code, contains('final String createdAt;'));
    });

    test('json_serializable adds annotations, part file and JsonKey for renamed fields', () {
      final r = gen.generate(['{"user_id":1}'],
          rootName: 'profile', options: const DartModelOptions(style: DartModelStyle.jsonSerializable));
      expect(r.code, contains("part 'profile.g.dart';"));
      expect(r.code, contains('@JsonSerializable()'));
      expect(r.code, contains("@JsonKey(name: 'user_id')"));
      expect(r.code, contains(r'_$ProfileFromJson(json)'));
    });

    test('freezed uses abstract class and the generated mixin', () {
      final r = gen.generate(['{"id":1}'], rootName: 'profile', options: const DartModelOptions(style: DartModelStyle.freezed));
      expect(r.code, contains('abstract class Profile with _\$Profile'));
      expect(r.code, contains("part 'profile.freezed.dart';"));
      expect(r.code, contains('required int id,'));
    });

    test('allNullable makes every field optional', () {
      final r = gen.generate(['{"id":1}'], options: const DartModelOptions(allNullable: true));
      expect(r.code, contains('final int? id;'));
    });

    test('a list of untyped values is cast, not mapped through an identity lambda', () {
      final r = gen.generate(['{"dynamic_fields":[]}']);
      expect(r.code, contains("json['dynamic_fields'] as List<dynamic>"));
      expect(r.code, isNot(contains('.map((e) => e)')));
    });

    group('allNullable (professional optional models)', () {
      const sample = '{"count":1,"status":true,"data":[{"fixed_fields":{"id":7,"is_revoked":false},"dynamic_fields":[]}]}';
      final r = gen.generate([sample], rootName: 'jobs_incremental_sync', options: const DartModelOptions(allNullable: true));

      test('fields are nullable and optional in the constructor', () {
        expect(r.code, contains('final int? count;'));
        expect(r.code, contains('final bool? status;'));
        expect(r.code, contains('final List<Data>? data;'));
        expect(r.code, contains('final List<dynamic>? dynamicFields;'));
        expect(r.code, isNot(contains('required ')));
        expect(r.code, contains('    this.count,'));
      });

      test('parsing tolerates absent values and skips stray list items', () {
        expect(r.code, contains("count: (json['count'] as num?)?.toInt(),"));
        expect(r.code, contains("status: json['status'] as bool?,"));
        expect(
          r.code,
          contains("(json['data'] as List<dynamic>?)?.whereType<Map<String, dynamic>>().map(Data.fromJson).toList()"),
        );
        expect(r.code, contains("dynamicFields: json['dynamic_fields'] as List<dynamic>?,"));
        expect(r.code, contains("json['fixed_fields'] == null ? null : FixedFields.fromJson(json['fixed_fields'] as Map<String, dynamic>)"));
      });

      test('toJson skips null fields', () {
        expect(r.code, contains("if (count != null) 'count': count,"));
        expect(r.code, contains("if (data != null) 'data': data!.map((e) => e.toJson()).toList(),"));
        expect(r.code, contains("if (fixedFields != null) 'fixed_fields': fixedFields!.toJson(),"));
      });

      test('copyWith is generated', () {
        expect(r.code, contains('JobsIncrementalSync copyWith({'));
        expect(r.code, contains('count: count ?? this.count,'));
        expect(r.code, contains('isRevoked: isRevoked ?? this.isRevoked,'));
      });

      test('a field with mixed types stays dynamic and optional', () {
        final m = gen.generate(['{"a":1}', '{"a":"x"}'], options: const DartModelOptions(allNullable: true));
        expect(m.code, contains('final dynamic a;'));
        expect(m.code, contains('    this.a,'));
        expect(m.code, contains('dynamic a,'));
      });

      test('dates parse leniently and encode only when present', () {
        final d = gen.generate(['{"created_at":"2026-10-02T10:00:00Z"}'], options: const DartModelOptions(allNullable: true));
        expect(d.code, contains("DateTime.tryParse((json['created_at'] as String?) ?? '')"));
        expect(d.code, contains("if (createdAt != null) 'created_at': createdAt!.toIso8601String(),"));
      });

      test('json_serializable leaves nulls out', () {
        final j = gen.generate(['{"id":1}'],
            options: const DartModelOptions(style: DartModelStyle.jsonSerializable, allNullable: true));
        expect(j.code, contains('@JsonSerializable(includeIfNull: false)'));
      });
    });

    test('a root list is accepted and noted', () {
      final r = gen.generate(['[{"id":1},{"id":2}]'], rootName: 'row');
      expect(r.classCount, 1);
      expect(r.notes.single, contains('list'));
    });

    test('reports invalid and empty input instead of throwing', () {
      expect(gen.generate(['not json']).code, isEmpty);
      expect(gen.generate(['not json']).notes, isNotEmpty);
      expect(gen.generate(['42']).notes.last, contains('no JSON object'));
      expect(gen.generate([]).code, isEmpty);
    });

    test('colliding class names are numbered', () {
      final r = gen.generate(['{"a":{"x":1},"b":{"a":{"y":2}}}'], rootName: 'root');
      // "a" appears as a field twice with different shapes: both become classes.
      expect(RegExp(r'class A\d?\b').allMatches(r.code).length, 2);
    });
  });
}
