import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../domain/entities/cloud_collection_entity.dart';
import '../../domain/entities/cloud_folder_entity.dart';
import '../../domain/entities/cloud_request_entity.dart';
import '../../domain/entities/collection_invite_entity.dart';
import '../../domain/entities/collection_member_entity.dart';
import '../../domain/entities/member_role.dart';
import '../../domain/repositories/team_repository.dart';

final class TeamRepositoryImpl implements TeamRepository {
  final SupabaseClient _client;
  const TeamRepositoryImpl(this._client);

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Sign in required');
    return id;
  }

  @override
  Future<List<CloudCollectionEntity>> listMyCollections() async {
    final rows = await _client
        .from('cloud_collections')
        .select('id, name, owner_id, collection_members!inner(user_id)')
        .eq('collection_members.user_id', _uid)
        .order('created_at', ascending: true);
    return rows.map(_toCollection).toList();
  }

  @override
  Future<CloudCollectionEntity> createCollection(String name) async {
    final row = await _client.from('cloud_collections').insert({'name': name, 'owner_id': _uid}).select().single();
    return _toCollection(row);
  }

  @override
  Future<void> renameCollection(int collectionId, String name) =>
      _client.from('cloud_collections').update({'name': name}).eq('id', collectionId);

  @override
  Future<void> deleteCollection(int collectionId) =>
      _client.from('cloud_collections').delete().eq('id', collectionId);

  @override
  Stream<List<CollectionMemberEntity>> watchMembers(int collectionId) => _client
      .from('collection_members')
      .stream(primaryKey: ['collection_id', 'user_id'])
      .eq('collection_id', collectionId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(_toMember).toList());

  @override
  Future<void> inviteMember(int collectionId, String email, MemberRole role) => _client.from('collection_invites').insert({
        'collection_id': collectionId,
        'email': email,
        'role': role.name,
        'invited_by': _uid,
      });

  @override
  Future<void> removeMember(int collectionId, String userId) =>
      _client.from('collection_members').delete().eq('collection_id', collectionId).eq('user_id', userId);

  @override
  Future<void> updateMemberRole(int collectionId, String userId, MemberRole role) => _client
      .from('collection_members')
      .update({'role': role.name}).eq('collection_id', collectionId).eq('user_id', userId);

  @override
  Future<List<CollectionInviteEntity>> listMyPendingInvites() async {
    final email = _client.auth.currentUser?.email;
    if (email == null) return const [];
    final rows = await _client
        .from('collection_invites')
        .select()
        .ilike('email', email)
        .isFilter('accepted_at', null)
        .order('created_at', ascending: true);
    return rows.map(_toInvite).toList();
  }

  @override
  Future<void> acceptInvite(int inviteId) => _client.rpc('accept_collection_invite', params: {'p_invite_id': inviteId});

  @override
  Future<List<CollectionInviteEntity>> listCollectionInvites(int collectionId) async {
    final rows = await _client
        .from('collection_invites')
        .select()
        .eq('collection_id', collectionId)
        .order('created_at', ascending: true);
    return rows.map(_toInvite).toList();
  }

  @override
  Stream<List<CloudFolderEntity>> watchFolders(int collectionId) => _client
      .from('cloud_folders')
      .stream(primaryKey: ['id'])
      .eq('collection_id', collectionId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(_toFolder).toList());

  @override
  Future<void> createFolder(int collectionId, String name, {int? parentFolderId}) => _client.from('cloud_folders').insert({
        'collection_id': collectionId,
        'parent_folder_id': parentFolderId,
        'name': name,
      });

  @override
  Future<void> renameFolder(int folderId, String name) =>
      _requireRow(_client.from('cloud_folders').update({'name': name}).eq('id', folderId).select('id'), 'Folder');

  @override
  Future<void> deleteFolder(int folderId) =>
      _requireRow(_client.from('cloud_folders').delete().eq('id', folderId).select('id'), 'Folder');

  @override
  Stream<List<CloudRequestEntity>> watchRequests(int collectionId) => _client
      .from('cloud_requests')
      .stream(primaryKey: ['id'])
      .eq('collection_id', collectionId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(_toRequest).toList());

  @override
  Future<CloudRequestEntity> createRequest(int collectionId, String name, {int? folderId}) async {
    final row = await _client
        .from('cloud_requests')
        .insert({
          'collection_id': collectionId,
          'folder_id': folderId,
          'name': name,
          'headers': const [],
          'query_params': const [],
          'body': const {'type': 'none'},
          'auth': const {'type': 'none'},
        })
        .select()
        .single();
    return _toRequest(row);
  }

  @override
  Future<void> updateRequest(CloudRequestEntity request, {CloudRequestEntity? base}) {
    final headers = _encodeHeaders(request.headers);
    final changes = <String, Object>{
      if (base == null || request.name != base.name) 'name': request.name,
      if (base == null || request.method != base.method) 'method': request.method,
      if (base == null || request.url != base.url) 'url': request.url,
      if (base == null || jsonEncode(headers) != jsonEncode(_encodeHeaders(base.headers))) 'headers': headers,
      if (base == null || request.body != base.body) 'body': _encodeBody(request.body),
    };
    if (changes.isEmpty) return Future.value();
    return _requireRow(_client.from('cloud_requests').update(changes).eq('id', request.id).select('id'), 'Request');
  }

  @override
  Future<void> moveRequest(int requestId, int? folderId) => _requireRow(
        _client.from('cloud_requests').update({'folder_id': folderId}).eq('id', requestId).select('id'),
        'Request',
      );

  @override
  Future<void> deleteRequest(int requestId) =>
      _requireRow(_client.from('cloud_requests').delete().eq('id', requestId).select('id'), 'Request');

  Future<void> _requireRow(PostgrestTransformBuilder<PostgrestList> write, String what) async {
    final rows = await write;
    if (rows.isEmpty) throw NotFoundException('$what no longer exists, or you lost edit access');
  }

  CloudCollectionEntity _toCollection(Map<String, dynamic> row) =>
      CloudCollectionEntity(id: row['id'] as int, name: row['name'] as String, ownerId: row['owner_id'] as String);

  CollectionMemberEntity _toMember(Map<String, dynamic> row) => CollectionMemberEntity(
        collectionId: row['collection_id'] as int,
        userId: row['user_id'] as String,
        role: MemberRole.fromString(row['role'] as String),
      );

  CollectionInviteEntity _toInvite(Map<String, dynamic> row) => CollectionInviteEntity(
        id: row['id'] as int,
        collectionId: row['collection_id'] as int,
        email: row['email'] as String,
        role: MemberRole.fromString(row['role'] as String),
        invitedBy: row['invited_by'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        accepted: row['accepted_at'] != null,
      );

  CloudFolderEntity _toFolder(Map<String, dynamic> row) => CloudFolderEntity(
        id: row['id'] as int,
        collectionId: row['collection_id'] as int,
        parentFolderId: row['parent_folder_id'] as int?,
        name: row['name'] as String,
      );

  CloudRequestEntity _toRequest(Map<String, dynamic> row) => CloudRequestEntity(
        id: row['id'] as int,
        collectionId: row['collection_id'] as int,
        folderId: row['folder_id'] as int?,
        name: row['name'] as String,
        method: row['method'] as String,
        url: row['url'] as String,
        headers: _decodeHeaders(row['headers']),
        body: _decodeBody(row['body']),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  List<KeyValueItem> _decodeHeaders(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && item['key'] != null)
          KeyValueItem(key: '${item['key']}', value: '${item['value'] ?? ''}', enabled: item['enabled'] != false),
    ];
  }

  List<Map<String, Object>> _encodeHeaders(List<KeyValueItem> headers) =>
      [for (final h in headers) {'key': h.key, 'value': h.value, 'enabled': h.enabled}];

  String _decodeBody(Object? raw) {
    if (raw is Map && raw['type'] == 'raw') return raw['content'] as String? ?? '';
    return '';
  }

  Map<String, String> _encodeBody(String body) => body.isEmpty ? const {'type': 'none'} : {'type': 'raw', 'content': body};
}
