import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Git object ids computed locally, so a file can be compared with what the
/// host reports without downloading it.
abstract final class GitHash {
  /// Same id `git hash-object` gives a file holding [text] (encoded as UTF-8).
  static String blobSha(String text) {
    final body = utf8.encode(text);
    final header = utf8.encode('blob ${body.length}\u0000');
    final bytes = Uint8List(header.length + body.length)
      ..setAll(0, header)
      ..setAll(header.length, body);
    return sha1.convert(bytes).toString();
  }
}
