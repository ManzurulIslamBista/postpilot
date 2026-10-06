/// Where a value sits inside a JSON body, written so that both a person and the assertion engine can read it.
///
/// A path is made of keys (`data.items`, or `data["a.b"]` for a key that is not a plain word) and a `[]` step for
/// "every element of this array". The `[]` form names a whole column of an array (`items[].id`) and is what a
/// baseline and the volatile-field lists use; [FieldPath.index] swaps it for a concrete position
/// (`items[0].id`) when a path has to be resolved by `JsonPathResolver`.
abstract final class FieldPath {
  static const root = '';

  static final _plainKey = RegExp(r'^[A-Za-z_][A-Za-z0-9_\-]*$');

  /// [key] below [parent]. Null for a key that cannot be written as a path the resolver reads back (`$`, or one
  /// holding both kinds of quote): such a field is left out of anything that needs a path.
  static String? child(String parent, String key) {
    if (_plainKey.hasMatch(key)) return parent.isEmpty ? key : '$parent.$key';
    if (key == r'$' || key.isEmpty) return null;
    if (!key.contains('"')) return '$parent["$key"]';
    if (!key.contains("'")) return "$parent['$key']";
    return null;
  }

  /// Every element of the array at [parent].
  static String element(String parent) => '$parent[]';

  /// The path of the array element at [position] when [path] runs through [arrayPath] (`items[]` becomes `items[0]`).
  static String index(String path, String arrayPath, int position) {
    final column = element(arrayPath);
    return path.startsWith(column) ? '$arrayPath[$position]${path.substring(column.length)}' : path;
  }

  /// The steps of [path] in order, each a key (`String`) or [elementStep].
  static List<Object> steps(String path) {
    final out = <Object>[];
    final key = StringBuffer();
    void flush() {
      if (key.isNotEmpty) out.add(key.toString());
      key.clear();
    }

    var i = 0;
    while (i < path.length) {
      final char = path[i];
      if (char == '.') {
        flush();
        i++;
      } else if (char == '[') {
        flush();
        if (path.startsWith('[]', i)) {
          out.add(elementStep);
          i += 2;
        } else {
          final quote = i + 1 < path.length ? path[i + 1] : '';
          final close = quote == '"' || quote == "'" ? path.indexOf('$quote]', i + 2) : -1;
          if (close == -1) {
            key.write(path.substring(i));
            break;
          }
          out.add(path.substring(i + 2, close));
          i = close + 2;
        }
      } else {
        key.write(char);
        i++;
      }
    }
    flush();
    return out;
  }

  /// The marker [steps] uses for "every element".
  static const elementStep = _ElementStep();

  /// A path rebuilt from [steps], the inverse of [FieldPath.steps].
  static String join(Iterable<Object> steps) {
    var path = root;
    for (final step in steps) {
      if (step is String) {
        path = child(path, step) ?? path;
      } else {
        path = element(path);
      }
    }
    return path;
  }

  /// Whether [path] goes through an array, so it has no single value.
  static bool crossesArray(String path) => steps(path).any((s) => s is! String);

  /// [path] is [prefix] or something below it (`a.b` and `a[]` are below `a`; `ab` is not; everything is below the root).
  static bool isUnder(String path, String prefix) {
    if (prefix.isEmpty || path == prefix) return true;
    if (!path.startsWith(prefix) || path.length == prefix.length) return false;
    final next = path[prefix.length];
    return next == '.' || next == '[';
  }

  /// The last key of [path] (the field's own name); empty for the root and for an array's elements.
  static String lastKey(String path) {
    final all = steps(path);
    return all.isNotEmpty && all.last is String ? all.last as String : '';
  }

  /// How many steps [path] has.
  static int depth(String path) => steps(path).length;

  /// [path] as it reads in a sentence: `body.items[*].id`, `body` for the whole body.
  static String display(String path) {
    if (path.isEmpty) return 'body';
    final shown = path.replaceAll('[]', '[*]');
    return shown.startsWith('[') ? 'body$shown' : 'body.$shown';
  }

  /// [path] with a leading `$` or `$.` removed and blanks trimmed: what two spellings of one path share.
  static String normalize(String path) {
    var text = path.trim();
    if (text.startsWith(r'$.')) {
      text = text.substring(2);
    } else if (text == r'$') {
      text = '';
    } else if (text.startsWith(r'$[')) {
      text = text.substring(1);
    }
    return text;
  }
}

final class _ElementStep {
  const _ElementStep();

  @override
  String toString() => '[]';
}
