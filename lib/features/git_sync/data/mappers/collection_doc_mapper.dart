import 'dart:convert';

import '../../../../core/database/app_database.dart' show Collection, CollectionAuthData, CollectionVariable;
import '../../../defaults/domain/entities/level_defaults.dart';
import '../../../defaults/domain/services/defaults_codec.dart';
import '../../../request_builder/data/models/request_json_codec.dart';
import '../../domain/entities/sync_doc.dart';
import 'doc_values.dart';

abstract final class CollectionDocMapper {
  static SyncDoc toDoc(
    Collection row, {
    required String uid,
    String description = '',
    List<String> tags = const [],
    List<CollectionVariable> variables = const [],
    CollectionAuthData? auth,
    LevelDefaults defaults = LevelDefaults.empty,
  }) =>
      canonical(SyncDoc(
        uid: uid,
        kind: SyncKind.collection,
        parentUid: null,
        name: row.name,
        data: {
          'description': description,
          'tags': tags,
          'variables': [
            for (final v in variables) {'key': v.key, 'value': v.value, 'enabled': v.enabled},
          ],
          'auth': auth == null ? null : jsonDecode(auth.authJson),
          // The headers and tests every request inherits; the collection's own variables and auth are the two keys above.
          ...DefaultsCodec.toDoc(defaults, includeVariablesAndAuth: false),
        },
      ));

  /// [doc] in the exact shape [toDoc] produces. [local] is the collection doc
  /// as it is stored now: credentials that [doc] leaves empty keep its values.
  static SyncDoc canonical(SyncDoc doc, {SyncDoc? local}) {
    final variables = DocValues.variables(doc.data['variables'], keepingSecretsOf: local?.data['variables']);
    final auth = DocValues.collectionAuth(doc.data['auth'], keepingSecretsOf: local?.data['auth']);
    return SyncDoc(
      uid: doc.uid,
      kind: SyncKind.collection,
      parentUid: null,
      name: doc.name,
      data: {
        ...DocValues.notes(doc.data, keepingSecretsOf: local?.data),
        if (variables.isNotEmpty) 'variables': variables,
        'auth': ?auth,
        ...DocValues.defaults(doc.data, keepingSecretsOf: local?.data, folder: false),
      },
    );
  }

  /// What the collection_auth row holds for [doc]; null when the row must go.
  static String? authJson(SyncDoc doc) {
    final auth = doc.data['auth'];
    return auth == null ? null : RequestJsonCodec.encodeAuth(DocValues.parseAuth(auth));
  }

  /// The headers and tests [doc] makes every request inherit, to write into `collection_defaults`.
  static LevelDefaults defaults(SyncDoc doc) => DefaultsCodec.fromDoc(doc.data, includeVariablesAndAuth: false);
}
