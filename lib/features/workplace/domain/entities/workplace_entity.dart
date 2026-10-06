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

  /// Blob sha of `workspace.json` in the repository as of the last push or pull:
  /// if the repository's sha differs when pushing, someone else changed it meanwhile.
  final String? lastSyncedSha;

  /// Name of the environment that was active when this workplace was last saved. A workspace
  /// file cannot say which one was active, so without this, switching to another workplace
  /// and back, or pulling, would leave no environment active. Per device: never written to workspace.json.
  final String? activeEnvironment;

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
    this.lastSyncedSha,
    this.activeEnvironment,
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
    Object? lastSyncedSha = _sentinel,
    Object? activeEnvironment = _sentinel,
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
        lastSyncedSha: lastSyncedSha == _sentinel ? this.lastSyncedSha : lastSyncedSha as String?,
        activeEnvironment: activeEnvironment == _sentinel ? this.activeEnvironment : activeEnvironment as String?,
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
        'lastSyncedSha': lastSyncedSha,
        'activeEnvironment': activeEnvironment,
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
        lastSyncedSha: json['lastSyncedSha'] as String?,
        activeEnvironment: json['activeEnvironment'] as String?,
      );
}
