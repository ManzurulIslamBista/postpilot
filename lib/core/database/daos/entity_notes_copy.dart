import '../app_database.dart';

/// Gives the duplicate [toId] the description and tags of [fromId]. [kind] is
/// `collection`, `folder` or `request`. Both are stored by kind and local id
/// with no foreign key to the entity, so a copied row does not bring them along.
Future<void> copyEntityNotes(AppDatabase db, String kind, {required int fromId, required int toId}) async {
  final markdown = await db.entityDocsDao.markdownOf(kind, fromId);
  if (markdown.isNotEmpty) await db.entityDocsDao.setMarkdown(kind, toId, markdown);
  final tags = await db.entityTagsDao.tagsOf(kind, fromId);
  if (tags.isNotEmpty) await db.entityTagsDao.setTags(kind, toId, tags);
}
