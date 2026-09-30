import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/team/domain/entities/cloud_request_entity.dart';
import 'package:postpilot/features/team/domain/services/cloud_request_mapper.dart';

CloudRequestEntity _cloud({String method = 'POST', String body = ''}) => CloudRequestEntity(
      id: 7,
      collectionId: 3,
      folderId: 2,
      name: 'Create user',
      method: method,
      url: 'https://api.example.com/users',
      headers: [KeyValueItem(key: 'X-Team', value: 'blue', enabled: false)],
      body: body,
      updatedAt: DateTime(2026),
    );

void main() {
  test('carries name, method, url and headers over, leaving auth on inherit', () {
    final local = CloudRequestMapper.toLocal(_cloud());

    expect(local.name, 'Create user');
    expect(local.method, HttpMethod.post);
    expect(local.url, 'https://api.example.com/users');
    expect(local.headers.single.key, 'X-Team');
    expect(local.headers.single.enabled, isFalse);
    expect(local.auth.type, AuthType.inherit);
  });

  test('a raw text body becomes a raw body, an empty one no body', () {
    final withBody = CloudRequestMapper.toLocal(_cloud(body: '{"name":"John"}'));
    expect(withBody.body.type, BodyType.raw);
    expect(withBody.body.rawText, '{"name":"John"}');

    expect(CloudRequestMapper.toLocal(_cloud()).body.type, BodyType.none);
  });

  test('an unknown method falls back to GET', () {
    expect(CloudRequestMapper.toLocal(_cloud(method: 'BREW')).method, HttpMethod.get);
  });
}
