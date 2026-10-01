import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_content.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_entity.dart';

void main() {
  late Directory tempDir;
  late WorkplaceRepositoryImpl repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('postpilot_workplace_test_');
    repository = WorkplaceRepositoryImpl();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('WorkplaceEntity & WorkplaceContent', () {
    test('serializes and deserializes workplace with classic token', () {
      final workplace = WorkplaceEntity(
        id: 'test-id',
        name: 'My Workspace',
        folderPath: tempDir.path,
        gitRepoUrl: 'https://github.com/owner/repo.git',
        gitBranch: 'main',
        gitToken: 'ghp_classicToken12345',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final json = workplace.toJson();
      expect(json['name'], 'My Workspace');
      expect(json['gitToken'], 'ghp_classicToken12345');
      expect(workplace.isGitConnected, isTrue);

      final restored = WorkplaceEntity.fromJson(json);
      expect(restored.id, workplace.id);
      expect(restored.name, workplace.name);
      expect(restored.gitToken, workplace.gitToken);
      expect(restored.gitBranch, workplace.gitBranch);
    });

    test('WorkplaceContent produces single JSON file format', () {
      final workplace = WorkplaceEntity(
        id: 'test-id',
        name: 'My Workspace',
        folderPath: tempDir.path,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final content = WorkplaceContent.empty(workplace);
      final jsonStr = content.toJsonString();

      expect(jsonStr, contains('"format": "postpilot-backup"'));
      expect(jsonStr, contains('"workplace"'));
      expect(jsonStr, contains('"collections"'));
      expect(jsonStr, contains('"environments"'));

      final decoded = WorkplaceContent.fromJsonString(jsonStr, fallbackWorkplace: workplace);
      expect(decoded.workplace.name, workplace.name);
    });
  });

  group('WorkplaceRepository local file operations', () {
    test('creates workplace and creates single workspace.json file on disk', () async {
      final folder = p.join(tempDir.path, 'project_alpha');
      final workplace = await repository.createWorkplace(
        name: 'Project Alpha',
        folderPath: folder,
      );

      expect(workplace.name, 'Project Alpha');
      expect(Directory(folder).existsSync(), isTrue);

      final jsonFile = File(p.join(folder, 'workspace.json'));
      expect(jsonFile.existsSync(), isTrue);

      final loadedContent = await repository.loadWorkplaceContent(workplace);
      expect(loadedContent.workplace.name, 'Project Alpha');
      expect(loadedContent.snapshot.collections, isEmpty);
    });

    test('syncWithGit throws when workplace is not connected to git', () async {
      final workplace = WorkplaceEntity(
        id: 'no-git',
        name: 'Local Only',
        folderPath: tempDir.path,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => repository.syncWithGit(workplace),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('not connected to a Git repository'),
        )),
      );
    });

    test('pullFromGit throws when workplace is not connected to git', () async {
      final workplace = WorkplaceEntity(
        id: 'no-git',
        name: 'Local Only',
        folderPath: tempDir.path,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => repository.pullFromGit(workplace),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('not connected to a Git repository'),
        )),
      );
    });
  });
}
