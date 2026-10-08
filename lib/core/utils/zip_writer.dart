import 'dart:convert';
import 'dart:typed_data';

/// A .zip of [files] (path inside the archive to content), built in memory for the browser build, which cannot write a
/// folder: the download is the only way to hand over a whole generated project.
///
/// Entries are stored, not compressed. The generated files are small text, and not compressing keeps the writer short
/// enough to check by eye against the format (PKWARE APPNOTE 4.3): local header, data, central directory, end record.
/// Names are UTF-8 (general purpose flag bit 11).
///
/// A path that is absolute, uses `\`, or has a `.`/`..`/empty segment is refused with an [ArgumentError], so an archive
/// can never write outside the folder it is extracted into. [modified] is the time stamped on every entry.
Uint8List buildZip(Map<String, List<int>> files, {DateTime? modified}) {
  if (files.length > 0xFFFF) throw ArgumentError.value(files.length, 'files', 'a zip holds at most 65535 files');
  final time = modified ?? DateTime.now();
  final dosTime = (time.hour << 11) | (time.minute << 5) | (time.second >> 1);
  final dosDate = ((time.year.clamp(1980, 2107) - 1980) << 9) | (time.month << 5) | time.day;

  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  for (final MapEntry(key: path, value: data) in files.entries) {
    _checkPath(path);
    final name = utf8.encode(path);
    final crc = crc32(data);
    final offset = out.length;
    if (offset + data.length > 0xFFFFFFFF) throw ArgumentError('The archive would be larger than 4 GB.');

    out
      ..add(_u32(0x04034b50))
      ..add(_u16(20)) // version needed
      ..add(_u16(0x0800)) // UTF-8 names
      ..add(_u16(0)) // stored
      ..add(_u16(dosTime))
      ..add(_u16(dosDate))
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(name.length))
      ..add(_u16(0)) // extra field length
      ..add(name)
      ..add(data);

    central
      ..add(_u32(0x02014b50))
      ..add(_u16(0x0314)) // made by: Unix, spec 2.0
      ..add(_u16(20))
      ..add(_u16(0x0800))
      ..add(_u16(0))
      ..add(_u16(dosTime))
      ..add(_u16(dosDate))
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(name.length))
      ..add(_u16(0)) // extra field length
      ..add(_u16(0)) // comment length
      ..add(_u16(0)) // disk number
      ..add(_u16(0)) // internal attributes
      ..add(_u32(0x81A40000)) // regular file, rw-r--r--
      ..add(_u32(offset))
      ..add(name);
  }

  final directoryOffset = out.length;
  final directory = central.takeBytes();
  out
    ..add(directory)
    ..add(_u32(0x06054b50))
    ..add(_u16(0)) // this disk
    ..add(_u16(0)) // disk with the directory
    ..add(_u16(files.length))
    ..add(_u16(files.length))
    ..add(_u32(directory.length))
    ..add(_u32(directoryOffset))
    ..add(_u16(0)); // comment length
  return out.takeBytes();
}

void _checkPath(String path) {
  final unsafe = path.isEmpty || path.startsWith('/') || path.contains('\\') || path.contains('\u0000');
  final segments = path.split('/');
  if (unsafe || segments.any((s) => s.isEmpty || s == '.' || s == '..')) {
    throw ArgumentError.value(path, 'path', 'is not a relative path inside the archive');
  }
}

final _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

/// The CRC-32 (IEEE 802.3, the one zip and gzip use) of [data].
int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final byte in data) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
