// Shared builders of the cleanup ledger tests: a request that creates something, and the answers a server gives to it.
import 'dart:convert';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

ApiRequestEntity createRequest({
  int id = 7,
  String name = 'Create partner',
  HttpMethod method = HttpMethod.post,
  String url = '{{baseUrl}}/partners',
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> queryParams = const [],
  RequestBody body = const RequestBody(type: BodyType.raw, rawText: '{"name": "Ann"}'),
  RequestAuth auth = const RequestAuth(type: AuthType.inherit),
  int collectionId = 3,
  int? folderId,
}) =>
    ApiRequestEntity(
      id: id,
      collectionId: collectionId,
      folderId: folderId,
      name: name,
      method: method,
      url: url,
      headers: headers,
      queryParams: queryParams,
      body: body,
      auth: auth,
    );

/// An Odoo JSON-2 create, as the Odoo Studio saves it.
ApiRequestEntity odooCreate({String model = 'res.partner', String name = 'Create partner', RequestBody? body}) => createRequest(
      name: name,
      url: '{{odooUrl}}/json/2/$model/create',
      headers: [
        KeyValueItem(key: 'Authorization', value: 'bearer {{odooApiKey}}'),
        KeyValueItem(key: 'X-Odoo-Database', value: '{{odooDb}}'),
        KeyValueItem(key: 'Content-Type', value: 'application/json; charset=utf-8'),
      ],
      body: body ?? const RequestBody(type: BodyType.raw, rawText: '{"vals_list": [{"name": "Ann"}]}'),
    );

String json(Object? value) => jsonEncode(value);

RequestBody rawBody(String text) => RequestBody(type: BodyType.raw, rawText: text);
