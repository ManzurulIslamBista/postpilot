import 'dart:convert';
import 'graphql_schema.dart';

/// A ready-to-send operation: the query text and the variables JSON it needs.
final class GqlOperation {
  final String query;
  final String variables;
  const GqlOperation(this.query, this.variables);
}

/// Writes an operation for a root field, so the person starts from something
/// that runs: arguments become variables, and the selection picks scalars and
/// descends into objects a few levels (never the same type twice in one path,
/// which would not end).
abstract final class GqlQueryBuilder {
  static GqlOperation forField(GqlSchema schema, String operation, GqlField field, {int depth = 2}) {
    final vars = <GqlArgument>[...field.args];
    final variableDefs = vars.isEmpty ? '' : '(${[for (final a in vars) '\$${a.name}: ${a.type}'].join(', ')})';
    final callArgs = vars.isEmpty ? '' : '(${[for (final a in vars) '${a.name}: \$${a.name}'].join(', ')})';
    final selection = _selection(schema, field.type.namedType, depth, {}, 1);
    final name = '${field.name[0].toUpperCase()}${field.name.substring(1)}';
    final query = StringBuffer('$operation $name$variableDefs {\n  ${field.name}$callArgs');
    query.write(selection.isEmpty ? '\n}' : ' $selection\n}');
    final variables = {for (final a in vars) a.name: _sample(schema, a.type, 0)};
    return GqlOperation(query.toString(), const JsonEncoder.withIndent('  ').convert(variables));
  }

  /// `{ id name author { id } }` for [typeName], two levels deep by default.
  static String _selection(GqlSchema schema, String typeName, int depth, Set<String> seen, int indent) {
    final type = schema.type(typeName);
    if (type == null || type.isScalarLike) return '';
    final pad = '  ' * (indent + 1);
    if (type.kind == 'UNION') {
      final parts = <String>[];
      for (final p in type.possibleTypes.take(4)) {
        final inner = _selection(schema, p, depth - 1, {...seen, typeName}, indent + 1);
        if (inner.isNotEmpty) parts.add('$pad... on $p $inner');
      }
      final close = '  ' * indent;
      return parts.isEmpty ? '{\n${pad}__typename\n$close}' : '{\n${pad}__typename\n${parts.join('\n')}\n$close}';
    }
    final lines = <String>[];
    for (final f in type.fields) {
      if (f.isDeprecated || f.args.any((a) => a.isRequired)) continue;
      final target = schema.type(f.type.namedType);
      // A type missing from the list can only be a scalar (every object type is listed).
      if (target == null || target.isScalarLike) {
        lines.add('$pad${f.name}');
      } else if (depth > 0 && !seen.contains(target.name) && target.name != typeName) {
        final inner = _selection(schema, target.name, depth - 1, {...seen, typeName}, indent + 1);
        if (inner.isNotEmpty) lines.add('$pad${f.name} $inner');
      }
      if (lines.length >= 14) break;
    }
    if (lines.isEmpty) return '{\n${pad}__typename\n${'  ' * indent}}';
    return '{\n${lines.join('\n')}\n${'  ' * indent}}';
  }

  /// A plausible value of [type] for the variables template.
  static Object? _sample(GqlSchema schema, GqlTypeRef type, int depth) {
    if (type.kind == 'NON_NULL') return _sample(schema, type.ofType!, depth);
    if (type.kind == 'LIST') return [_sample(schema, type.ofType!, depth)];
    final t = schema.type(type.name ?? '');
    switch (type.name) {
      case 'Int':
        return 0;
      case 'Float':
        return 0.0;
      case 'Boolean':
        return false;
      case 'ID':
      case 'String':
        return '';
    }
    if (t == null) return null;
    if (t.kind == 'ENUM') return t.enumValues.firstOrNull?.name;
    if (t.kind == 'INPUT_OBJECT' && depth < 3) {
      return {for (final f in t.inputFields) f.name: _sample(schema, f.type, depth + 1)};
    }
    return null;
  }
}
