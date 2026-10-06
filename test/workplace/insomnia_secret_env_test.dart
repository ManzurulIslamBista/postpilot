import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_insomnia_usecase.dart';
import '../support/in_memory_import_export_fakes.dart';

/// An Insomnia v4 export with one workspace, a base environment and a "Prod" sub-environment with [data].
String _export(Map<String, dynamic> data) => jsonEncode({
      '_type': 'export',
      '__export_format': 4,
      '__export_source': 'insomnia.desktop.app:v2023.5.8',
      'resources': [
        {'_id': 'wrk_1', '_type': 'workspace', 'parentId': null, 'name': 'Shop', 'scope': 'collection'},
        {'_id': 'env_base', '_type': 'environment', 'parentId': 'wrk_1', 'name': 'Base Environment', 'data': {'base_url': 'https://shop.test'}, 'metaSortKey': 1},
        {'_id': 'env_prod', '_type': 'environment', 'parentId': 'env_base', 'name': 'Prod', 'data': data, 'metaSortKey': 2},
      ],
    });

void main() {
  late InMemoryDb db;
  late ImportInsomniaUseCase useCase;

  setUp(() {
    db = InMemoryDb();
    useCase = ImportInsomniaUseCase(db.writer, db.collectionRepository, db.environmentRepository);
  });

  test('environment variables named like credentials, or holding a token, are imported as secrets', () async {
    await useCase(_export({
      'api_key': 'k-1',
      'db_password': 'pw-1',
      'accessToken': 'at-1',
      'X-Auth-Token': 'x-1',
      'notes': 'ghp_abcdefghijklmnopqrstuvwxyz0123456789',
      'base_url': 'https://prod.shop.test',
      'debug': true,
      'token_url': 'https://auth.shop.test/token',
      'author': 'ada',
    }));

    final secret = {for (final v in db.environmentVariables) v.key: v.isSecret};
    expect(secret, {
      'api_key': true,
      'db_password': true,
      'accessToken': true,
      'X-Auth-Token': true,
      'notes': true,
      'base_url': false,
      'debug': false,
      'token_url': false,
      'author': false,
    });
  });

  test('the values themselves are imported unchanged', () async {
    await useCase(_export({'api_key': 'k-1', 'base_url': 'https://prod.shop.test'}));

    expect({for (final v in db.environmentVariables) v.key: v.value}, {'api_key': 'k-1', 'base_url': 'https://prod.shop.test'});
  });
}
