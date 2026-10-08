import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/zip_writer.dart';

// Expected CRCs come from python's zlib.crc32 (crc32(b"123456789") = 0xcbf43926 is the standard check value).

class _Entry {
  final String name;
  final int crc;
  final int size;
  final int offset;
  final int method;
  final int flags;
  const _Entry(this.name, this.crc, this.size, this.offset, this.method, this.flags);
}

/// Reads the central directory the way an unzip tool does: from the end record, never trusting the local headers.
List<_Entry> _readDirectory(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  final end = zip.length - 22;
  expect(data.getUint32(end, Endian.little), 0x06054b50, reason: 'end of central directory signature');
  final count = data.getUint16(end + 10, Endian.little);
  expect(data.getUint16(end + 8, Endian.little), count);
  final directorySize = data.getUint32(end + 12, Endian.little);
  var at = data.getUint32(end + 16, Endian.little);
  expect(at + directorySize, end, reason: 'the directory ends where the end record starts');
  final entries = <_Entry>[];
  for (var i = 0; i < count; i++) {
    expect(data.getUint32(at, Endian.little), 0x02014b50);
    final flags = data.getUint16(at + 8, Endian.little);
    final method = data.getUint16(at + 10, Endian.little);
    final crc = data.getUint32(at + 16, Endian.little);
    final compressed = data.getUint32(at + 20, Endian.little);
    final size = data.getUint32(at + 24, Endian.little);
    final nameLength = data.getUint16(at + 28, Endian.little);
    final extraLength = data.getUint16(at + 30, Endian.little);
    final commentLength = data.getUint16(at + 32, Endian.little);
    final offset = data.getUint32(at + 42, Endian.little);
    expect(compressed, size, reason: 'stored, so both sizes are equal');
    final name = utf8.decode(zip.sublist(at + 46, at + 46 + nameLength));
    entries.add(_Entry(name, crc, size, offset, method, flags));
    at += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

Uint8List _contentOf(Uint8List zip, _Entry e) {
  final data = ByteData.sublistView(zip);
  expect(data.getUint32(e.offset, Endian.little), 0x04034b50, reason: 'local header signature of ${e.name}');
  final nameLength = data.getUint16(e.offset + 26, Endian.little);
  final extraLength = data.getUint16(e.offset + 28, Endian.little);
  final start = e.offset + 30 + nameLength + extraLength;
  return zip.sublist(start, start + e.size);
}

void main() {
  group('crc32', () {
    test('matches the standard check value and python for other inputs', () {
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
      expect(crc32(utf8.encode('hello world')), 0x0D4A1185);
      expect(crc32(utf8.encode('héllo €')), 0xE131580E);
      expect(crc32(const []), 0);
    });
  });

  group('buildZip', () {
    final when = DateTime(2026, 10, 7, 12, 34, 56);

    test('holds every file with its name, size, crc and exact content', () {
      final files = {
        'app/lib/hello.dart': utf8.encode('hello world'),
        'app/pubspec.yaml': utf8.encode('123456789'),
        'app/README.md': utf8.encode('héllo €'),
        'app/empty.txt': <int>[],
      };
      final zip = buildZip(files, modified: when);
      final entries = _readDirectory(zip);

      expect([for (final e in entries) e.name], files.keys.toList());
      expect([for (final e in entries) e.crc], [0x0D4A1185, 0xCBF43926, 0xE131580E, 0]);
      expect([for (final e in entries) e.size], [11, 9, 10, 0], reason: 'bytes, not characters: "héllo €" is 7 characters and 10 bytes (python: len(s.encode()))');
      expect(entries.every((e) => e.method == 0), isTrue, reason: 'stored');
      expect(entries.every((e) => e.flags & 0x0800 != 0), isTrue, reason: 'UTF-8 names');
      for (final e in entries) {
        expect(_contentOf(zip, e), files[e.name], reason: e.name);
      }
    });

    test('stamps the given time in MS-DOS format', () {
      final zip = buildZip({'a.txt': const [1]}, modified: when);
      final data = ByteData.sublistView(zip);
      // 12:34:56 -> 12 << 11 | 34 << 5 | 28 ; 2026-10-07 -> (2026 - 1980) << 9 | 10 << 5 | 7
      expect(data.getUint16(10, Endian.little), 12 << 11 | 34 << 5 | 28);
      expect(data.getUint16(12, Endian.little), (2026 - 1980) << 9 | 10 << 5 | 7);
    });

    test('an empty archive is just the end record', () {
      final zip = buildZip(const {}, modified: when);
      expect(zip.length, 22);
      expect(ByteData.sublistView(zip).getUint32(0, Endian.little), 0x06054b50);
    });

    test('refuses a path that could leave the folder it is extracted into', () {
      for (final bad in ['../evil.txt', 'a/../../evil.txt', '/etc/passwd', r'a\b.txt', 'a//b.txt', './a.txt', '', 'a/']) {
        expect(() => buildZip({bad: const [1]}), throwsArgumentError, reason: '"$bad"');
      }
    });
  });
}
