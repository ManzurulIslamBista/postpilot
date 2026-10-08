import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../test_suggestions/domain/services/volatility.dart';
import '../entities/matrix_grid.dart';

/// How two bodies are compared.
enum MatrixCompareMode {
  /// Keys, types and the values that are not volatile (ids, timestamps, tokens, counters are ignored).
  full('Structure and values'),

  /// Only keys and types: dev and prod data differ, their shape should not.
  structure('Structure only');

  final String label;
  const MatrixCompareMode(this.label);
}

/// What a cell's body is, for comparing it.
enum MatrixBodyKind { none, json, text }

/// A body read once: its kind and, for JSON, the decoded document.
final class MatrixBody {
  final MatrixBodyKind kind;
  final Object? json;
  final String text;

  const MatrixBody._(this.kind, this.json, this.text);

  static const none = MatrixBody._(MatrixBodyKind.none, null, '');

  /// The body of [cell]. A body cut at the size limit is never JSON: whatever parses from half a document is not it.
  factory MatrixBody.of(MatrixCell? cell) {
    final text = cell?.body ?? '';
    if (cell == null || !cell.hasResponse || text.trim().isEmpty) return none;
    if (!cell.bodyTruncated) {
      try {
        return MatrixBody._(MatrixBodyKind.json, jsonDecode(text), text);
      } on FormatException {
        // plain text
      }
    }
    return MatrixBody._(MatrixBodyKind.text, null, text.trim());
  }

  /// The document with its volatile values and, for [MatrixCompareMode.structure], its values replaced, ready to be
  /// compared or hashed. Text and nothing are returned as they are.
  Object? comparable(MatrixCompareMode mode) {
    if (kind != MatrixBodyKind.json) return kind == MatrixBodyKind.text ? text : null;
    return mode == MatrixCompareMode.full ? neutralise(json) : shapeOf(json);
  }

  /// What a volatile value is replaced with, in a diff and in the fingerprint.
  static const volatileMark = '~';

  /// [value] with every volatile string or number replaced by [volatileMark]: a field that changes on its own (see
  /// `Volatility`: by its name `createdAt`, `id`, `token`... or by what the value looks like, a UUID, a date, a JWT).
  /// A list's items count under the key of the list. `null` and booleans stay: a token that is `null` for one caller
  /// and a string for another is a difference worth seeing.
  static Object? neutralise(Object? value, [String key = '']) {
    if (value is Map) {
      return {for (final e in value.entries) '${e.key}': neutralise(e.value, '${e.key}')};
    }
    if (value is List) return [for (final item in value) neutralise(item, key)];
    if ((value is String || value is num) && Volatility.reason(key, value) != null) return volatileMark;
    return value;
  }

  /// The shape of [value]: every scalar becomes its type, a list becomes a list of the shape of its first item (and an
  /// empty one stays empty, since nothing is known about its items).
  static Object? shapeOf(Object? value) {
    if (value is Map) return {for (final e in value.entries) '${e.key}': shapeOf(e.value)};
    if (value is List) return value.isEmpty ? <Object?>[] : [shapeOf(value.first)];
    if (value == null) return 'null';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    return 'string';
  }

  /// JSON text of [value] with the keys of every object in alphabetical order, so two documents that differ only in
  /// key order produce the same text.
  static String canonical(Object? value) => jsonEncode(_sorted(value));

  static Object? _sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _sorted(value[k])};
    }
    if (value is List) return [for (final item in value) _sorted(item)];
    return value;
  }

  /// The six leading hex digits of the SHA-256 of [text].
  static String shortHash(String text) => sha256.convert(utf8.encode(text)).toString().substring(0, 6);

  /// A short readable stand-in for the cell's body: `{3 keys} #4f2a9c`, `[12 items] #a1b2c3`, `text, 41 chars #0badc0`,
  /// `empty`, `error`, `not sent`. The hash is that of the document as [mode] compares it, so two bodies that compare
  /// equal have the same hash.
  static String fingerprint(MatrixCell? cell, MatrixCompareMode mode) {
    if (cell == null) return 'not run';
    if (cell.error != null) return 'error';
    if (cell.note != null) return 'not sent';
    final body = MatrixBody.of(cell);
    switch (body.kind) {
      case MatrixBodyKind.none:
        return 'empty';
      case MatrixBodyKind.text:
        return 'text, ${body.text.length} chars #${shortHash(body.text)}';
      case MatrixBodyKind.json:
        final doc = body.json;
        final hash = shortHash(canonical(body.comparable(mode)));
        final size = switch (doc) {
          Map() => doc.length == 1 ? '{1 key}' : '{${doc.length} keys}',
          List() => doc.length == 1 ? '[1 item]' : '[${doc.length} items]',
          _ => 'JSON value',
        };
        return '$size #$hash';
    }
  }
}
