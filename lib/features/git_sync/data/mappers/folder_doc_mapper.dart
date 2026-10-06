import '../../../../core/database/app_database.dart' show Folder;
import '../../../defaults/domain/entities/level_defaults.dart';
import '../../../defaults/domain/services/defaults_codec.dart';
import '../../domain/entities/sync_doc.dart';
import 'doc_values.dart';

abstract final class FolderDocMapper {
  static SyncDoc toDoc(
    Folder row, {
    required String uid,
    required String parentUid,
    String description = '',
    List<String> tags = const [],
    LevelDefaults defaults = LevelDefaults.empty,
  }) =>
      canonical(SyncDoc(
        uid: uid,
        kind: SyncKind.folder,
        parentUid: parentUid,
        name: row.name,
        order: row.orderIndex,
        data: {'description': description, 'tags': tags, ...DefaultsCodec.toDoc(defaults)},
      ));

  /// [doc] in the exact shape [toDoc] produces. [local] is the folder doc as it
  /// is stored now: credentials its description, headers, variables, auth and tests lost keep their local text.
  /// What the folder passes down to its requests (`headers`, `variables`, `auth`, `tests`) is part of the doc.
  static SyncDoc canonical(SyncDoc doc, {SyncDoc? local}) => SyncDoc(
        uid: doc.uid,
        kind: SyncKind.folder,
        parentUid: doc.parentUid,
        name: doc.name,
        order: doc.order,
        data: {
          ...DocValues.notes(doc.data, keepingSecretsOf: local?.data),
          ...DocValues.defaults(doc.data, keepingSecretsOf: local?.data, folder: true),
        },
      );

  /// What the folder passes down according to [doc], to write into `folder_defaults`.
  static LevelDefaults defaults(SyncDoc doc) => DefaultsCodec.fromDoc(doc.data);
}
