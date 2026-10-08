// The pure logic of a matrix run: columns, identities, which fields count as volatile, how two answers are compared,
// which rows differ, which cells break an expectation, and the Markdown / CSV / text exports. Every expected value is
// worked out by hand (the hashes with Python's hashlib), none comes from calling the code under test.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_column.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_grid.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_identity.dart';
import 'package:postpilot/features/matrix_run/domain/services/matrix_analysis.dart';
import 'package:postpilot/features/matrix_run/domain/services/matrix_body.dart';
import 'package:postpilot/features/matrix_run/domain/services/matrix_comparator.dart';
import 'package:postpilot/features/matrix_run/domain/services/matrix_exporter.dart';
import 'package:postpilot/features/matrix_run/domain/services/matrix_read_only.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/response_tools/domain/services/json_diff.dart';

MatrixCell _cell(int status, String? body, {int ms = 10}) => MatrixCell.text(status: status, duration: Duration(milliseconds: ms), body: body);

void main() {
  group('identities and columns', () {
    test('an empty value clears the variable; an identity of only cleared variables is anonymous', () {
      const anonymous = MatrixIdentity(id: 'a', name: 'anonymous', variables: {'token': '', 'apiKey': ''});
      const admin = MatrixIdentity(id: 'b', name: 'admin', variables: {'token': 'abc', 'apiKey': ''});
      expect(anonymous.cleared, {'token', 'apiKey'});
      expect(anonymous.isAnonymous, isTrue);
      expect(admin.cleared, {'apiKey'});
      expect(admin.isAnonymous, isFalse);
      expect(const MatrixIdentity(id: 'c', name: 'nobody').isAnonymous, isFalse, reason: 'sets nothing, clears nothing');
    });

    test('an identity survives a JSON round trip, and a damaged one is dropped instead of thrown', () {
      const admin = MatrixIdentity(id: 'b', name: 'admin', variables: {'token': 'abc', 'apiKey': ''});
      expect(MatrixIdentity.fromJson(admin.toJson()), admin);
      expect(MatrixIdentity.fromJson('nope'), isNull);
      expect(MatrixIdentity.fromJson({'name': 'x'}), isNull, reason: 'no id');
      expect(MatrixIdentity.fromJson({'id': '', 'name': 'x'}), isNull);
      final lenient = MatrixIdentity.fromJson({'id': 'z', 'name': 'u', 'variables': {' token ': 7, '': 'dropped', 'k': null}})!;
      expect(lenient.variables, {'token': '7', 'k': ''});
    });

    test('columns are every environment with every identity, environment by environment', () {
      const admin = MatrixIdentity(id: 'a', name: 'admin');
      const user = MatrixIdentity(id: 'u', name: 'user');
      expect(MatrixColumn.product(['Dev', 'Prod'], [admin, user]).map((c) => c.label), ['Dev · admin', 'Dev · user', 'Prod · admin', 'Prod · user']);
      expect(MatrixColumn.product(['Dev', 'Prod'], const []).map((c) => c.label), ['Dev', 'Prod']);
      expect(MatrixColumn.product(const [], [admin, user]).map((c) => c.label), ['admin', 'user']);
      expect(MatrixColumn.product(const [], const []), isEmpty);
      expect(const MatrixColumn().label, 'Active environment');
    });

    test('a column key tells the environment and the identity apart', () {
      const a = MatrixIdentity(id: 'a', name: 'admin');
      expect(const MatrixColumn(environment: 'Dev').key, isNot(const MatrixColumn(environment: 'Dev', identity: a).key));
      expect(const MatrixColumn(environment: 'Dev', identity: a), const MatrixColumn(environment: 'Dev', identity: a));
      expect(const MatrixColumn(environment: 'Dev', identity: a).overrides, isEmpty);
      expect(MatrixColumn(identity: a.copyWith(variables: {'t': '1'})).overrides, {'t': '1'});
    });

    test('read-only means GET, HEAD and OPTIONS and nothing else', () {
      expect([for (final m in HttpMethod.values) if (MatrixReadOnly.allows(m)) m.label], ['GET', 'HEAD', 'OPTIONS']);
      expect(MatrixReadOnly.allowsLabel('get'), isTrue);
      expect(MatrixReadOnly.allowsLabel('POST'), isFalse);
    });
  });

  group('volatile fields', () {
    test('ids, dates, counters and token-looking values are replaced; everything else stays', () {
      final doc = {
        'id': 7,
        'name': 'Ann',
        'createdAt': '2026-10-01T10:00:00Z',
        'token': null,
        'tags': ['a'],
        'total': 12,
        'uuidField': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        'active': true,
        'nested': {'updated_at': 1700000000, 'city': 'Dhaka'},
        'refs': [
          {'ref': '2026-10-01'},
          {'ref': 'plain'},
        ],
      };
      expect(MatrixBody.neutralise(doc), {
        'id': '~',
        'name': 'Ann',
        'createdAt': '~',
        'token': null,
        'tags': ['a'],
        'total': '~',
        'uuidField': '~',
        'active': true,
        'nested': {'updated_at': '~', 'city': 'Dhaka'},
        'refs': [
          {'ref': '~'},
          {'ref': 'plain'},
        ],
      });
    });

    test('the shape keeps keys and types, one item of a list, and an empty list empty', () {
      expect(
        MatrixBody.shapeOf({
          'a': 1,
          'b': 'x',
          'c': [
            {'d': true},
            {'d': false},
          ],
          'e': [],
          'f': null,
          'g': 2.5,
        }),
        {
          'a': 'number',
          'b': 'string',
          'c': [
            {'d': 'boolean'},
          ],
          'e': [],
          'f': 'null',
          'g': 'number',
        },
      );
    });

    test('canonical text sorts the keys of every object', () {
      expect(MatrixBody.canonical({'b': 1, 'a': {'d': 2, 'c': 3}}), '{"a":{"c":3,"d":2},"b":1}');
    });

    test('a body cut at the size limit is text, whatever it starts with', () {
      final cut = MatrixCell.text(status: 200, duration: Duration.zero, body: '{"a":1');
      expect(MatrixBody.of(cut).kind, MatrixBodyKind.text);
      expect(MatrixBody.of(_cell(200, '{"a":1}')).kind, MatrixBodyKind.json);
      expect(MatrixBody.of(_cell(200, '  ')).kind, MatrixBodyKind.none);
      expect(MatrixBody.of(const MatrixCell.failed('boom')).kind, MatrixBodyKind.none);
    });
  });

  group('fingerprints', () {
    test('JSON: size and the first six hex digits of the SHA-256 of the volatile-free canonical text', () {
      // sha256('{"id":"~","name":"Ann"}') and sha256('{"id":"number","name":"string"}')
      final cell = _cell(200, '{"name":"Ann","id":41}');
      expect(MatrixBody.fingerprint(cell, MatrixCompareMode.full), '{2 keys} #8ae188');
      expect(MatrixBody.fingerprint(cell, MatrixCompareMode.structure), '{2 keys} #17d409');
      expect(MatrixBody.fingerprint(_cell(200, '{"a":1}'), MatrixCompareMode.full), '{1 key} #015abd');
      expect(MatrixBody.fingerprint(_cell(200, '[1, 2, 3]'), MatrixCompareMode.full), '[3 items] #a615ee');
      expect(MatrixBody.fingerprint(_cell(200, '[7]'), MatrixCompareMode.full), startsWith('[1 item] #'));
    });

    test('two answers that differ only in a volatile field have the same fingerprint', () {
      final a = _cell(200, '{"id":1,"name":"Ann","createdAt":"2026-10-01T10:00:00Z"}');
      final b = _cell(200, '{"createdAt":"2027-01-01T00:00:00Z","name":"Ann","id":999}');
      expect(MatrixBody.fingerprint(a, MatrixCompareMode.full), MatrixBody.fingerprint(b, MatrixCompareMode.full));
    });

    test('text, empty, error, not sent and not run', () {
      expect(MatrixBody.fingerprint(_cell(200, 'hello world'), MatrixCompareMode.full), 'text, 11 chars #b94d27');
      expect(MatrixBody.fingerprint(_cell(204, ''), MatrixCompareMode.full), 'empty');
      expect(MatrixBody.fingerprint(const MatrixCell.failed('x'), MatrixCompareMode.full), 'error');
      expect(MatrixBody.fingerprint(const MatrixCell.notSent('x'), MatrixCompareMode.full), 'not sent');
      expect(MatrixBody.fingerprint(null, MatrixCompareMode.full), 'not run');
    });
  });

  group('comparing two answers', () {
    CellComparison compare(MatrixCell? a, MatrixCell? b, [MatrixCompareMode mode = MatrixCompareMode.full]) => MatrixComparator.compare(a, b, mode: mode);

    test('volatile fields are ignored: new ids and dates are not a difference', () {
      final c = compare(
        _cell(200, '{"id":1,"name":"Ann","createdAt":"2026-10-01T10:00:00Z"}'),
        _cell(200, '{"id":2,"name":"Ann","createdAt":"2026-10-02T11:30:00Z"}'),
      );
      expect(c.differs, isFalse);
      expect(c.reasons, isEmpty);
    });

    test('a changed value is one field that differs, with its path and both values', () {
      final c = compare(_cell(200, '{"id":1,"name":"Ann"}'), _cell(200, '{"id":2,"name":"Bob"}'));
      expect((c.differs, c.statusDiffers, c.bodyDiffers), (true, false, true));
      expect(c.reasons, ['body: 1 field differs']);
      expect(c.changes.single.kind, JsonChangeKind.changed);
      expect((c.changes.single.path, c.changes.single.before, c.changes.single.after), ('name', 'Ann', 'Bob'));
    });

    test('a removed and an added key are two fields', () {
      final c = compare(_cell(200, '{"a":1,"b":2}'), _cell(200, '{"a":1,"c":3}'));
      expect(c.reasons, ['body: 2 fields differ']);
      expect({for (final x in c.changes) x.kind: x.path}, {JsonChangeKind.removed: 'b', JsonChangeKind.added: 'c'});
    });

    test('a different status is named first, with both codes', () {
      final c = compare(_cell(200, '{"items":[1]}'), _cell(403, '{"error":"forbidden"}'));
      expect((c.statusDiffers, c.bodyDiffers), (true, true));
      expect(c.reasons, ['status 200 vs 403', 'body: 2 fields differ']);
    });

    test('the same status and an identical body is no difference', () {
      expect(compare(_cell(404, '{"error":"missing"}'), _cell(404, '{"error":"missing"}')).differs, isFalse);
      expect(compare(_cell(204, ''), _cell(204, null)).differs, isFalse);
    });

    test('structure only: other data of the same shape does not differ, a changed type does', () {
      final a = _cell(200, '{"data":[{"name":"Ann"},{"name":"Bob"}]}');
      final b = _cell(200, '{"data":[{"name":"Zed"}]}');
      expect(compare(a, b, MatrixCompareMode.structure).differs, isFalse);
      final values = compare(a, b);
      expect(values.reasons, ['body: 2 fields differ']);
      expect({for (final x in values.changes) x.path: x.kind}, {'data[0].name': JsonChangeKind.changed, 'data[1]': JsonChangeKind.removed});

      final typed = compare(_cell(200, '{"a":1}'), _cell(200, '{"a":"1"}'), MatrixCompareMode.structure);
      expect(typed.differs, isTrue);
      expect((typed.changes.single.path, typed.changes.single.before, typed.changes.single.after), ('a', 'number', 'string'));
    });

    test('structure only: an empty list against a list with items says nothing about their shape', () {
      final empty = _cell(200, '{"data":[]}');
      final full = _cell(200, '{"data":[{"name":"x"}]}');
      expect(compare(empty, full, MatrixCompareMode.structure).differs, isFalse);
      expect(compare(empty, full).reasons, ['body: 1 field differs'], reason: 'with values it is an added item');
      // A key missing from the items still shows.
      final missing = compare(_cell(200, '{"data":[{"name":"x","age":1}]}'), full, MatrixCompareMode.structure);
      expect(missing.changes.single.path, 'data[0].age');
    });

    test('a token that is null for one caller and a string for another differs even though tokens are volatile', () {
      final c = compare(_cell(200, '{"token":null}'), _cell(200, '{"token":"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefg"}'));
      expect(c.differs, isTrue);
      expect(c.changes.single.path, 'token');
    });

    test('kinds of body: text against text, JSON against text, empty against content', () {
      expect(compare(_cell(200, 'ok'), _cell(200, 'ok  ')).differs, isFalse, reason: 'whitespace around text is ignored');
      expect(compare(_cell(200, 'ok'), _cell(200, 'no')).reasons, ['body differs']);
      expect(compare(_cell(200, '{"a":1}'), _cell(200, 'plain')).reasons, ['body: JSON vs text']);
      expect(compare(_cell(200, ''), _cell(200, '{"a":1}')).reasons, ['body: empty vs JSON']);
    });

    test('an answer against a failure differs; two failures are the same outcome; a cell not run is not compared as a failure', () {
      expect(compare(_cell(200, '{}'), const MatrixCell.failed('refused')).reasons, ['200 vs error']);
      expect(compare(const MatrixCell.failed('dev.test refused'), const MatrixCell.failed('prod.test refused')).differs, isFalse);
      expect(compare(const MatrixCell.notSent('Run if'), _cell(200, '{}')).reasons, ['not sent vs 200']);
      expect(compare(const MatrixCell.failed('x'), const MatrixCell.notSent('y')).reasons, ['error vs not sent']);
      expect(compare(null, _cell(200, '{}')).reasons, ['not run vs 200']);
    });
  });

  group('expectations', () {
    test('access is 2xx and denial is 401 or 403', () {
      expect([199, 200, 299, 300].map((s) => MatrixAccess.isAllowed(_cell(s, ''))), [false, true, true, false]);
      expect([401, 403, 404, 200].map((s) => MatrixAccess.isDenied(_cell(s, ''))), [true, true, false, false]);
      expect(MatrixAccess.isAllowed(const MatrixCell.failed('x')), isFalse);
      expect(MatrixAccess.isDenied(null), isFalse);
    });

    test('allowed where deny was expected, and denied where access was expected, are the unexpected accesses', () {
      expect(MatrixAccess.unexpected(MatrixExpect.deny, _cell(200, '')), 'Unexpected access: allowed (200) where denial was expected');
      expect(MatrixAccess.unexpected(MatrixExpect.allow, _cell(403, '')), 'Unexpected access: denied (403) where access was expected');
      expect(MatrixAccess.unexpected(MatrixExpect.allow, _cell(200, '')), isNull);
      expect(MatrixAccess.unexpected(MatrixExpect.allow, _cell(299, '')), isNull);
      expect(MatrixAccess.unexpected(MatrixExpect.deny, _cell(401, '')), isNull);
      expect(MatrixAccess.unexpected(MatrixExpect.deny, _cell(403, '')), isNull);
    });

    test('a status that is neither access nor denial is unexpected whichever was expected', () {
      expect(MatrixAccess.unexpected(MatrixExpect.allow, _cell(404, '')), 'Unexpected: HTTP 404, access was expected');
      expect(MatrixAccess.unexpected(MatrixExpect.deny, _cell(500, '')), 'Unexpected: HTTP 500, denial was expected');
      expect(MatrixAccess.unexpected(MatrixExpect.allow, const MatrixCell.failed('x')), 'Unexpected: no answer, access was expected');
      expect(MatrixAccess.unexpected(MatrixExpect.deny, const MatrixCell.failed('x')), 'Unexpected: no answer, denial was expected');
    });

    test('nothing is said without an expectation, for a request not sent, or for a cell not run', () {
      expect(MatrixAccess.unexpected(MatrixExpect.none, _cell(500, '')), isNull);
      expect(MatrixAccess.unexpected(MatrixExpect.allow, const MatrixCell.notSent('declined')), isNull);
      expect(MatrixAccess.unexpected(MatrixExpect.deny, null), isNull);
    });
  });

  group('analysis of a grid', () {
    const dev = MatrixColumn(environment: 'Dev');
    const staging = MatrixColumn(environment: 'Staging');
    const prod = MatrixColumn(environment: 'Prod');

    MatrixGrid grid() {
      final g = MatrixGrid([dev, staging, prod], [
        MatrixRow(key: 'r1', name: 'List', method: 'GET', columns: 3),
        MatrixRow(key: 'r2', name: 'Secret', method: 'GET', columns: 3),
        MatrixRow(key: 'r3', name: 'Ping', method: 'GET', columns: 3),
      ]);
      g.setCell('r1', 0, _cell(200, '{"items":[1]}'));
      g.setCell('r1', 1, _cell(200, '{"items":[1]}'));
      g.setCell('r1', 2, _cell(200, '{"items":[1]}'));
      g.setCell('r2', 0, _cell(200, '{"items":[1]}'));
      g.setCell('r2', 1, _cell(200, '{"items":[1]}'));
      g.setCell('r2', 2, _cell(403, '{"error":"forbidden"}'));
      g.setCell('r3', 0, _cell(200, 'pong'));
      return g;
    }

    test('a row differs when any column differs from the first; a cell not run is not a difference', () {
      final a = MatrixAnalysis.of(grid());
      expect(a.rows.map((r) => r.differs), [false, true, false]);
      expect(a.differingRows, 1);
      expect(a.rows[1].cells.map((c) => c.differs), [false, false, true]);
      expect(a.rows[1].reasons, ['Prod: status 200 vs 403, body: 2 fields differ']);
      expect(a.rows[2].cells[1].comparison, isNull, reason: 'Staging has not answered yet');
    });

    test('expectations per request and column mark the unexpected cells', () {
      final a = MatrixAnalysis.of(grid(), expectations: {
        'r2': {dev.key: MatrixExpect.deny, staging.key: MatrixExpect.allow, prod.key: MatrixExpect.deny},
        'r1': {prod.key: MatrixExpect.allow},
      });
      expect(a.unexpectedCells, 1);
      expect(a.rows[1].cells[0].unexpected, 'Unexpected access: allowed (200) where denial was expected');
      expect(a.rows[1].cells[1].isUnexpected, isFalse);
      expect(a.rows[1].cells[2].isUnexpected, isFalse, reason: '403 is the denial that was expected');
      expect(a.rows[0].hasUnexpected, isFalse);
      expect(a.rows[1].hasUnexpected, isTrue);
    });

    test('the compare mode changes what differs', () {
      final g = MatrixGrid([dev, prod], [MatrixRow(key: 'r1', name: 'List', method: 'GET', columns: 2)]);
      g.setCell('r1', 0, _cell(200, '{"data":[{"name":"Ann"}]}'));
      g.setCell('r1', 1, _cell(200, '{"data":[{"name":"Bob"}]}'));
      expect(MatrixAnalysis.of(g).differingRows, 1);
      expect(MatrixAnalysis.of(g, mode: MatrixCompareMode.structure).differingRows, 0);
    });
  });

  group('exports', () {
    const dev = MatrixColumn(environment: 'Dev');
    const prod = MatrixColumn(environment: 'Prod');

    MatrixAnalysis analysis({String secondName = 'Get user'}) {
      final g = MatrixGrid([dev, prod], [
        MatrixRow(key: 'r1', name: 'List orders', method: 'GET', folder: 'Orders', columns: 2),
        MatrixRow(key: 'r2', name: secondName, method: 'GET', columns: 2),
      ]);
      g.setCell('r1', 0, _cell(200, '{"items":[1,2]}', ms: 12));
      g.setCell('r1', 1, _cell(200, '{"items":[1,2]}', ms: 15));
      g.setCell('r2', 0, _cell(200, '{"name":"Ann"}', ms: 8));
      g.setCell('r2', 1, _cell(403, '{"error":"no"}', ms: 9));
      return MatrixAnalysis.of(g, expectations: {
        'r2': {prod.key: MatrixExpect.allow},
      });
    }

    test('Markdown: a table with a result column, the unexpected results listed, and a summary', () {
      expect(
        MatrixExporter.markdown(analysis(), title: 'Orders matrix'),
        '## Orders matrix\n'
        '\n'
        'Compared: structure and values. Columns: Dev, Prod; the first column is the reference.\n'
        '\n'
        '| Request | Dev | Prod | Result |\n'
        '| --- | --- | --- | --- |\n'
        '| Orders / GET List orders | 200 · 12 ms · {1 key} #02d216 | 200 · 15 ms · {1 key} #02d216 | same |\n'
        '| GET Get user | 200 · 8 ms · {1 key} #fb782b | 403 · 9 ms · {1 key} #42c258 (UNEXPECTED) | DIFFERS: Prod: status 200 vs 403, body: 2 fields differ |\n'
        '\n'
        'Unexpected results:\n'
        '- GET Get user in Prod: Unexpected access: denied (403) where access was expected\n'
        '\n'
        '1 of 2 requests differ. 1 unexpected result.\n',
      );
    });

    test('Markdown: a pipe or a line break in a name cannot break the table', () {
      final md = MatrixExporter.markdown(analysis(secondName: 'a|b\nc'));
      expect(md, contains(r'| GET a\|b c |'));
    });

    test('CSV: one line per request with status, time and fingerprint per column, quoted where it needs to be', () {
      expect(
        MatrixExporter.csv(analysis()),
        'request,method,folder,Dev status,Dev ms,Dev body,Prod status,Prod ms,Prod body,differs,differences,unexpected\n'
        'List orders,GET,Orders,200,12,{1 key} #02d216,200,15,{1 key} #02d216,no,,\n'
        'Get user,GET,,200,8,{1 key} #fb782b,403,9,{1 key} #42c258,yes,"Prod: status 200 vs 403, body: 2 fields differ",Prod: Unexpected access: denied (403) where access was expected',
      );
    });

    test('CSV: a name that would run as a formula in a spreadsheet is defused', () {
      final csv = MatrixExporter.csv(analysis(secondName: '=HYPERLINK("x")'));
      expect(csv, contains("'=HYPERLINK"));
    });

    test('failures, requests not sent and cells not run read plainly in every export', () {
      final g = MatrixGrid([dev, prod], [MatrixRow(key: 'r1', name: 'Boom', method: 'GET', columns: 2)]);
      g.setCell('r1', 0, const MatrixCell.failed('The URL still contains {{host}}'));
      final a = MatrixAnalysis.of(g);
      expect(MatrixExporter.cellText(g.rows.first.cells[0], a.mode), 'ERR The URL still contains {{host}}');
      expect(MatrixExporter.cellText(const MatrixCell.notSent('Run if did not hold'), a.mode), 'not sent: Run if did not hold');
      expect(MatrixExporter.cellText(null, a.mode), 'not run');
      expect(MatrixExporter.cellText(MatrixCell.failed('x' * 100), a.mode), 'ERR ${'x' * 60}…');
      expect(MatrixExporter.csv(a), contains('Boom,GET,,,,ERR The URL still contains {{host}},,,not run,no,,'));
    });

    test('text: a block per request, the differing columns marked', () {
      final text = MatrixExporter.text(analysis(), title: 'Orders');
      expect(text, startsWith('Orders (structure and values; the first column is the reference)\n\nOrders / GET List orders\n'));
      expect(text, contains('  Dev   200 · 12 ms · {1 key} #02d216\n'));
      expect(text, contains('  Prod  403 · 9 ms · {1 key} #42c258   <- differs: status 200 vs 403, body: 2 fields differ; Unexpected access: denied (403) where access was expected\n'));
      expect(text, endsWith('1 of 2 requests differ. 1 unexpected result.\n'));
    });

    test('the summary says so when nothing differs', () {
      final g = MatrixGrid([dev, prod], [MatrixRow(key: 'r1', name: 'Ping', method: 'GET', columns: 2)]);
      g.setCell('r1', 0, _cell(200, 'pong'));
      g.setCell('r1', 1, _cell(200, 'pong'));
      expect(MatrixExporter.markdown(MatrixAnalysis.of(g)), endsWith('No request differs between the columns.\n'));
    });
  });
}
