import '../../../../core/database/daos/entity_docs_dao.dart';
import '../../domain/entities/entity_kind.dart';
import '../../domain/repositories/documentation_repository.dart';

final class DocumentationRepositoryImpl implements DocumentationRepository {
  final EntityDocsDao _dao;
  const DocumentationRepositoryImpl(this._dao);

  @override
  Future<String> markdownOf(EntityKind kind, int id) => _dao.markdownOf(kind.dbValue, id);

  @override
  Future<void> setMarkdown(EntityKind kind, int id, String text) => _dao.setMarkdown(kind.dbValue, id, text);

  @override
  Future<Map<int, String>> markdownByLocalId(EntityKind kind) => _dao.markdownByLocalId(kind.dbValue);
}
