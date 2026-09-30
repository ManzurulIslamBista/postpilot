import 'package:drift/drift.dart';
import 'collections_table.dart';

/// Named `GitLinkRow` so it does not clash with the domain `GitLink`.
@DataClassName('GitLinkRow')
class GitLinks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get collectionId => integer().unique().references(Collections, #id, onDelete: KeyAction.cascade)();
  TextColumn get provider => text()();
  TextColumn get owner => text()();
  TextColumn get repo => text()();
  TextColumn get branch => text()();
  TextColumn get basePath => text().withDefault(const Constant(''))();
  TextColumn get lastSyncedSha => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get includeSecrets => boolean().withDefault(const Constant(false))();
}

/// The last state shared with the remote, one row per synced doc of a link.
class GitBaseEntries extends Table {
  IntColumn get linkId => integer().references(GitLinks, #id, onDelete: KeyAction.cascade)();
  TextColumn get uid => text()();
  TextColumn get path => text()();
  TextColumn get blobSha => text()();
  TextColumn get docJson => text()();

  @override
  Set<Column> get primaryKey => {linkId, uid};
}
