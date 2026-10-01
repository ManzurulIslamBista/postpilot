final class WorkplaceEntity {
  final String id;
  final String name;
  final String folderPath;
  final String? gitRepoUrl;
  final String gitBranch;
  final String? gitToken;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSyncedAt;

  const WorkplaceEntity({
    required this.id,
    required this.name,
    required this.folderPath,
    this.gitRepoUrl,
    this.gitBranch = 'main',
    this.gitToken,
    required this.createdAt,
    required this.updatedAt,
    this.lastSyncedAt,
  });

  bool get isGitConnected => gitRepoUrl != null && gitRepoUrl!.trim().isNotEmpty;

  static const Object _sentinel = Object();

  WorkplaceEntity copyWith({
    String? name,
    String? folderPath,
    Object? gitRepoUrl = _sentinel,
    String? gitBranch,
    Object? gitToken = _sentinel,
    DateTime? updatedAt,
    Object? lastSyncedAt = _sentinel,
  }) =>
      WorkplaceEntity(
        id: id,
        name: name ?? this.name,
        folderPath: folderPath ?? this.folderPath,
        gitRepoUrl: gitRepoUrl == _sentinel ? this.gitRepoUrl : gitRepoUrl as String?,
        gitBranch: gitBranch ?? this.gitBranch,
        gitToken: gitToken == _sentinel ? this.gitToken : gitToken as String?,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastSyncedAt: lastSyncedAt == _sentinel ? this.lastSyncedAt : lastSyncedAt as DateTime?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'folderPath': folderPath,
        'gitRepoUrl': gitRepoUrl,
        'gitBranch': gitBranch,
        'gitToken': gitToken,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
      };

  factory WorkplaceEntity.fromJson(Map<String, dynamic> json) => WorkplaceEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        folderPath: json['folderPath'] as String,
        gitRepoUrl: json['gitRepoUrl'] as String?,
        gitBranch: (json['gitBranch'] as String?)?.isNotEmpty == true ? json['gitBranch'] as String : 'main',
        gitToken: json['gitToken'] as String?,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
        lastSyncedAt: json['lastSyncedAt'] != null ? DateTime.tryParse(json['lastSyncedAt'].toString()) : null,
      );
}
