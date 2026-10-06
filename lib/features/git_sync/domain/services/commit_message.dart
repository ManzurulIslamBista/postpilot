import '../entities/git_sync_results.dart';
import '../entities/sync_doc.dart';

/// A commit message written from what changed, the way a workplace push writes one: a subject that counts the
/// changes ("Add 1 folder, change 2 requests in Users API") and the first names under it, one per line, so the
/// Git history of a collection says more than "Update 3 item(s)".
abstract final class CommitMessage {
  static const _namesShown = 3;
  static const _subjectLimit = 72;

  /// "Update [collectionName]" when [changes] is empty or [collectionName] is all there is to say.
  static String fromChanges(String collectionName, List<DocChange> changes) {
    final collection = collectionName.trim();
    if (changes.isEmpty) return collection.isEmpty ? 'Update collection' : 'Update $collection';

    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    int count(DocChangeType type, SyncKind kind) => changes.where((c) => c.type == type && c.kind == kind).length;

    final parts = <String>[];
    for (final (verb, type) in const [
      ('add', DocChangeType.added),
      ('change', DocChangeType.modified),
      ('remove', DocChangeType.deleted),
    ]) {
      final requests = count(type, SyncKind.request);
      final folders = count(type, SyncKind.folder);
      final bits = [
        if (requests > 0) plural(requests, 'request'),
        if (folders > 0) plural(folders, 'folder'),
      ];
      if (bits.isNotEmpty) parts.add('$verb ${bits.join(' and ')}');
    }
    if (changes.any((c) => c.kind == SyncKind.collection)) parts.add('update the collection settings');

    final subject = parts.join(', ');
    final line = '${subject[0].toUpperCase()}${subject.substring(1)}${collection.isEmpty ? '' : ' in $collection'}';

    final items = [for (final c in changes) if (c.kind != SyncKind.collection) c.name];
    final named = items.take(_namesShown).map((name) => '- $name').toList();
    final body = named.isEmpty ? '' : '\n\n${named.join('\n')}${items.length > _namesShown ? '\n- …' : ''}';
    return '${line.length > _subjectLimit ? '${line.substring(0, _subjectLimit - 3)}...' : line}$body';
  }
}
