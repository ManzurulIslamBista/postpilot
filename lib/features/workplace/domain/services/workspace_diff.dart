import 'dart:convert';

enum WorkspaceChangeKind { added, removed, changed }

/// One thing that differs between two copies of a workspace.
final class WorkspaceChange {
  final WorkspaceChangeKind kind;

  /// `Collection`, `Request`, `Environment`, `Variable`, `Global`.
  final String scope;
  final String label;

  /// Where it lives: the collection of a request, the environment of a variable.
  final String? container;

  const WorkspaceChange(this.kind, this.scope, this.label, {this.container});
}

final class WorkspaceChangeSummary {
  final List<WorkspaceChange> changes;
  const WorkspaceChangeSummary(this.changes);

  bool get isEmpty => changes.isEmpty;
  int count(WorkspaceChangeKind kind, [String? scope]) =>
      changes.where((c) => c.kind == kind && (scope == null || c.scope == scope)).length;

  /// "Add 2 requests, change 1 request, update the Dev environment": what a
  /// teammate reading the Git history wants to know.
  String commitMessage() {
    if (isEmpty) return 'Update workspace from PostPilot';
    final parts = <String>[];
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

    for (final (verb, kind) in [('add', WorkspaceChangeKind.added), ('change', WorkspaceChangeKind.changed), ('remove', WorkspaceChangeKind.removed)]) {
      final requests = count(kind, 'Request');
      final collections = count(kind, 'Collection');
      final bits = [
        if (collections > 0) plural(collections, 'collection'),
        if (requests > 0) plural(requests, 'request'),
      ];
      if (bits.isNotEmpty) parts.add('$verb ${bits.join(' and ')}');
    }
    final envs = {for (final c in changes) if (c.scope == 'Environment' || c.scope == 'Variable') c.container ?? c.label};
    if (envs.isNotEmpty) parts.add('update ${envs.length == 1 ? 'the ${envs.first} environment' : plural(envs.length, 'environment')}');
    if (count(WorkspaceChangeKind.added, 'Global') + count(WorkspaceChangeKind.changed, 'Global') + count(WorkspaceChangeKind.removed, 'Global') > 0) {
      parts.add('update global variables');
    }
    var subject = parts.join(', ');
    subject = '${subject[0].toUpperCase()}${subject.substring(1)}';

    // Name a few of the requests, so the log says more than a count.
    final named = [for (final c in changes) if (c.scope == 'Request') c.label].take(3).toList();
    final collections = {for (final c in changes) if (c.scope == 'Request' && c.container != null) c.container!};
    final where = collections.length == 1 ? ' in ${collections.first}' : '';
    final body = named.isEmpty ? '' : '\n\n${named.map((n) => '- $n').join('\n')}${count(WorkspaceChangeKind.added) + count(WorkspaceChangeKind.changed) + count(WorkspaceChangeKind.removed) > named.length ? '\n- …' : ''}';
    final line = '$subject$where';
    return '${line.length > 72 ? '${line.substring(0, 69)}...' : line}$body';
  }
}

/// Compares two `workspace.json` documents by what a person sees, not by
/// position or database id: collections by name, requests by folder path and
/// name, environments and their variables by name.
abstract final class WorkspaceDiff {
  /// [before] is the older copy (the repository's), [after] the newer (the local file).
  /// Either may be null (no file yet), meaning an empty workspace.
  static WorkspaceChangeSummary compare(String? before, String? after) {
    final a = _read(before);
    final b = _read(after);
    final changes = <WorkspaceChange>[];

    final aCollections = _byName(a['collections']);
    final bCollections = _byName(b['collections']);
    for (final name in {...aCollections.keys, ...bCollections.keys}) {
      final ca = aCollections[name];
      final cb = bCollections[name];
      if (ca == null) {
        changes.add(WorkspaceChange(WorkspaceChangeKind.added, 'Collection', name));
        for (final r in _requests(cb!).keys) {
          changes.add(WorkspaceChange(WorkspaceChangeKind.added, 'Request', r, container: name));
        }
      } else if (cb == null) {
        changes.add(WorkspaceChange(WorkspaceChangeKind.removed, 'Collection', name));
      } else {
        final ra = _requests(ca);
        final rb = _requests(cb);
        for (final key in {...ra.keys, ...rb.keys}) {
          if (ra[key] == null) {
            changes.add(WorkspaceChange(WorkspaceChangeKind.added, 'Request', key, container: name));
          } else if (rb[key] == null) {
            changes.add(WorkspaceChange(WorkspaceChangeKind.removed, 'Request', key, container: name));
          } else if (ra[key] != rb[key]) {
            changes.add(WorkspaceChange(WorkspaceChangeKind.changed, 'Request', key, container: name));
          }
        }
        // Variables and auth of the collection itself.
        if (_sig(ca['variables']) != _sig(cb['variables']) || _sig(ca['auth']) != _sig(cb['auth'])) {
          changes.add(WorkspaceChange(WorkspaceChangeKind.changed, 'Collection', '$name (variables or auth)'));
        }
      }
    }

    final aEnvs = _byName(a['environments']);
    final bEnvs = _byName(b['environments']);
    for (final name in {...aEnvs.keys, ...bEnvs.keys}) {
      final ea = aEnvs[name];
      final eb = bEnvs[name];
      if (ea == null) {
        changes.add(WorkspaceChange(WorkspaceChangeKind.added, 'Environment', name));
      } else if (eb == null) {
        changes.add(WorkspaceChange(WorkspaceChangeKind.removed, 'Environment', name));
      } else {
        final va = _variables(ea['variables']);
        final vb = _variables(eb['variables']);
        for (final key in {...va.keys, ...vb.keys}) {
          final kind = va[key] == null
              ? WorkspaceChangeKind.added
              : vb[key] == null
                  ? WorkspaceChangeKind.removed
                  : va[key] != vb[key]
                      ? WorkspaceChangeKind.changed
                      : null;
          if (kind != null) changes.add(WorkspaceChange(kind, 'Variable', key, container: name));
        }
      }
    }

    final ga = _variables(a['globals']);
    final gb = _variables(b['globals']);
    for (final key in {...ga.keys, ...gb.keys}) {
      final kind = ga[key] == null
          ? WorkspaceChangeKind.added
          : gb[key] == null
              ? WorkspaceChangeKind.removed
              : ga[key] != gb[key]
                  ? WorkspaceChangeKind.changed
                  : null;
      if (kind != null) changes.add(WorkspaceChange(kind, 'Global', key));
    }
    return WorkspaceChangeSummary(changes);
  }

  static Map<String, dynamic> _read(String? text) {
    if (text == null || text.trim().isEmpty) return const {};
    try {
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : const {};
    } on FormatException {
      return const {};
    }
  }

  static Map<String, Map<String, dynamic>> _byName(Object? list) {
    final out = <String, Map<String, dynamic>>{};
    if (list is! List) return out;
    final seen = <String, int>{};
    for (final item in list.whereType<Map<String, dynamic>>()) {
      final name = '${item['name'] ?? ''}';
      final n = (seen[name] ?? 0) + 1;
      seen[name] = n;
      out[n == 1 ? name : '$name#$n'] = item;
    }
    return out;
  }

  /// Requests of [collection] by `folder/path/name` (with the method, so two
  /// requests of the same name but different methods stay apart), each as a
  /// signature that ignores database ids.
  static Map<String, String> _requests(Map<String, dynamic> collection) {
    final folders = <Object?, Map<String, dynamic>>{
      for (final f in (collection['folders'] is List ? collection['folders'] as List : const []).whereType<Map<String, dynamic>>()) f['id']: f,
    };
    String pathOf(Object? folderId) {
      final names = <String>[];
      var current = folderId;
      var guard = 0;
      while (current != null && folders[current] != null && guard++ < 50) {
        names.insert(0, '${folders[current]!['name']}');
        current = folders[current]!['parentId'];
      }
      return names.isEmpty ? '' : '${names.join('/')}/';
    }

    final out = <String, String>{};
    final seen = <String, int>{};
    for (final r in (collection['requests'] is List ? collection['requests'] as List : const []).whereType<Map<String, dynamic>>()) {
      final base = '${pathOf(r['folderId'])}${r['name'] ?? ''}';
      final n = (seen[base] ?? 0) + 1;
      seen[base] = n;
      final copy = {...r}
        ..remove('folderId')
        ..remove('uid');
      out[n == 1 ? base : '$base#$n'] = jsonEncode(copy);
    }
    return out;
  }

  static Map<String, String> _variables(Object? list) {
    final out = <String, String>{};
    if (list is! List) return out;
    for (final v in list.whereType<Map<String, dynamic>>()) {
      out['${v['key'] ?? ''}'] = '${v['value']}|${v['enabled']}|${v['secret']}';
    }
    return out;
  }

  static String _sig(Object? v) => jsonEncode(v ?? const {});
}
