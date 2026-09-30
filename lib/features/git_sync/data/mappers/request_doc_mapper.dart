import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../../../core/database/app_database.dart' show Request, RequestScript, RequestsCompanion;
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../request_builder/data/models/request_json_codec.dart';
import '../../domain/entities/sync_doc.dart';
import 'doc_values.dart';

abstract final class RequestDocMapper {
  static SyncDoc toDoc(
    Request row, {
    required String uid,
    required String parentUid,
    RequestScript? scripts,
    String? settingsJson,
    String description = '',
    List<String> tags = const [],
  }) =>
      canonical(SyncDoc(
        uid: uid,
        kind: SyncKind.request,
        parentUid: parentUid,
        name: row.name,
        order: row.orderIndex,
        data: {
          'method': row.method,
          'url': row.url,
          'headers': jsonDecode(row.headersJson),
          'queryParams': jsonDecode(row.queryParamsJson),
          'body': {
            'type': row.bodyType,
            'rawContentType': row.rawContentType,
            'rawText': row.bodyText,
            'formFields': jsonDecode(row.formFieldsJson),
            'urlEncodedFields': jsonDecode(row.urlEncodedFieldsJson),
            'graphqlQuery': row.graphqlQuery,
            'graphqlVariables': row.graphqlVariables,
          },
          'auth': RequestJsonCodec.decodeAuth(row.authType, row.authConfigJson).toJson(),
          'tests': {
            'assertions': DocValues.decodeList(scripts?.assertionsJson),
            'extractors': DocValues.decodeList(scripts?.extractorsJson),
          },
          'settings': DocValues.decodeMap(settingsJson),
          'description': description,
          'tags': tags,
        },
      ));

  /// [doc] in the exact shape [toDoc] produces. [local] is the request doc as
  /// it is stored now: credentials that [doc] leaves empty keep its values.
  static SyncDoc canonical(SyncDoc doc, {SyncDoc? local}) {
    final data = doc.data;
    final body = data['body'] as Map? ?? const {};
    final tests = data['tests'] as Map? ?? const {};
    final assertions = DocValues.jsonList(tests['assertions']);
    final extractors = DocValues.jsonList(tests['extractors']);
    final settings = DocValues.jsonMap(data['settings']);
    return SyncDoc(
      uid: doc.uid,
      kind: SyncKind.request,
      parentUid: doc.parentUid,
      name: doc.name,
      order: doc.order,
      data: {
        'method': HttpMethod.fromString(data['method'] as String?).name,
        'url': data['url'] as String? ?? '',
        'headers': DocValues.keyValues(data['headers']),
        'queryParams': DocValues.keyValues(data['queryParams']),
        'body': {
          'type': DocValues.enumName(BodyType.values, body['type'], BodyType.none),
          'rawContentType': DocValues.enumName(RawContentType.values, body['rawContentType'], RawContentType.json),
          'rawText': body['rawText'] as String? ?? '',
          'formFields': DocValues.keyValues(body['formFields']),
          'urlEncodedFields': DocValues.keyValues(body['urlEncodedFields']),
          'graphqlQuery': body['graphqlQuery'] as String? ?? '',
          'graphqlVariables': body['graphqlVariables'] as String? ?? '{}',
        },
        'auth': DocValues.requestAuth(data['auth'], keepingSecretsOf: local?.data['auth']),
        if (assertions.isNotEmpty || extractors.isNotEmpty)
          'tests': {'assertions': assertions, 'extractors': extractors},
        if (settings.isNotEmpty) 'settings': settings,
        ...DocValues.notes(data),
      },
    );
  }

  /// Every `requests` column [doc] (in [canonical] form) determines, except
  /// the owning collection.
  static RequestsCompanion toCompanion(SyncDoc doc, {required int? folderId}) {
    final data = doc.data;
    final body = data['body'] as Map;
    final auth = DocValues.parseAuth(data['auth'] as Object);
    return RequestsCompanion(
      folderId: Value(folderId),
      name: Value(doc.name),
      method: Value(data['method'] as String),
      url: Value(data['url'] as String),
      headersJson: Value(RequestJsonCodec.encodeKeyValues(DocValues.keyValueItems(data['headers']))),
      queryParamsJson: Value(RequestJsonCodec.encodeKeyValues(DocValues.keyValueItems(data['queryParams']))),
      bodyType: Value(body['type'] as String),
      rawContentType: Value(body['rawContentType'] as String),
      bodyText: Value(body['rawText'] as String),
      formFieldsJson: Value(RequestJsonCodec.encodeKeyValues(DocValues.keyValueItems(body['formFields']))),
      urlEncodedFieldsJson: Value(RequestJsonCodec.encodeKeyValues(DocValues.keyValueItems(body['urlEncodedFields']))),
      graphqlQuery: Value(body['graphqlQuery'] as String),
      graphqlVariables: Value(body['graphqlVariables'] as String),
      authType: Value(auth.type.name),
      authConfigJson: Value(RequestJsonCodec.encodeAuth(auth)),
      orderIndex: Value(doc.order),
      updatedAt: Value(DateTime.now()),
    );
  }
}
