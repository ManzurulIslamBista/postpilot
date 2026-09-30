// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'git_links_dao.dart';

// ignore_for_file: type=lint
mixin _$GitLinksDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $GitLinksTable get gitLinks => attachedDatabase.gitLinks;
  $GitBaseEntriesTable get gitBaseEntries => attachedDatabase.gitBaseEntries;
  GitLinksDaoManager get managers => GitLinksDaoManager(this);
}

class GitLinksDaoManager {
  final _$GitLinksDaoMixin _db;
  GitLinksDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$GitLinksTableTableManager get gitLinks =>
      $$GitLinksTableTableManager(_db.attachedDatabase, _db.gitLinks);
  $$GitBaseEntriesTableTableManager get gitBaseEntries =>
      $$GitBaseEntriesTableTableManager(
        _db.attachedDatabase,
        _db.gitBaseEntries,
      );
}
