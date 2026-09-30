import '../../../../core/database/app_database.dart' show Folder;
import '../../domain/entities/sync_doc.dart';
import 'doc_values.dart';

abstract final class FolderDocMapper {
  static SyncDoc toDoc(
    Folder row, {
    required String uid,
    required String parentUid,
    String description = '',
    List<String> tags = const [],
  }) =>
      canonical(SyncDoc(
        uid: uid,
        kind: SyncKind.folder,
        parentUid: parentUid,
        name: row.name,
        order: row.orderIndex,
        data: {'description': description, 'tags': tags},
      ));

  /// [doc] in the exact shape [toDoc] produces.
  static SyncDoc canonical(SyncDoc doc) => SyncDoc(
        uid: doc.uid,
        kind: SyncKind.folder,
        parentUid: doc.parentUid,
        name: doc.name,
        order: doc.order,
        data: DocValues.notes(doc.data),
      );
}
