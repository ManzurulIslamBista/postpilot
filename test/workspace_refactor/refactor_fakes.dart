// Stand-ins for the repositories, for tests of the applier and the dialog: a workspace that is a fixed snapshot, and a
// writer that records what it is asked to write instead of writing it.
import 'package:postpilot/features/workspace_refactor/domain/entities/unit_field.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/workspace_snapshot.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/refactor_writer.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/workspace_reader.dart';

final class FixedSource implements WorkspaceSource {
  WorkspaceSnapshot snapshot;
  FixedSource(this.snapshot);

  @override
  Future<WorkspaceSnapshot> read() async => snapshot;
}

typedef Write = ({String key, Set<String> groups, RefactorUnit current, RefactorUnit target});

final class RecordingWriter implements RefactorWriter {
  final writes = <Write>[];
  final deleted = <String>[];
  final recreated = <String>[];

  /// The n-th write (1-based) throws.
  int? failOnWrite;

  @override
  Future<Map<int, int>> write(RefactorUnit current, RefactorUnit target, Set<String> groups) async {
    writes.add((key: target.key, groups: groups, current: current, target: target));
    if (writes.length == failOnWrite) throw StateError('disk full');
    return {
      // A saved example is saved again under a new id, as the real writer does.
      for (final g in groups)
        if (g.startsWith('example.')) int.parse(g.substring(8)): 900 + int.parse(g.substring(8)),
    };
  }

  @override
  Future<void> delete(RefactorUnit unit) async => deleted.add(unit.key);

  @override
  Future<void> recreate(RefactorUnit unit) async => recreated.add(unit.key);
}
