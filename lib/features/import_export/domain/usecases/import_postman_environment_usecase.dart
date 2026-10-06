import 'package:flutter/foundation.dart' show compute;
import '../../../../core/usecases/usecase.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/entities/global_variable_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../services/postman_environment_parser.dart';

/// Imports an exported Postman environment as a new environment, or a Postman
/// globals file into the global variables. Nothing existing is overwritten: an
/// environment whose name is taken gets "(imported)" added, and a global that
/// already exists is kept as it is and reported. If saving fails midway
/// everything this import created is removed again.
final class ImportPostmanEnvironmentUseCase implements UseCase<ImportSummary, String> {
  final EnvironmentRepository _environmentRepository;
  final GlobalVariableRepository _globalVariableRepository;

  const ImportPostmanEnvironmentUseCase(this._environmentRepository, this._globalVariableRepository);

  @override
  Future<ImportSummary> call(String json) async {
    final parsed = await compute(PostmanEnvironmentParser.parse, json.replaceFirst('﻿', '').trim());
    return parsed.isGlobals ? _importGlobals(parsed) : _importEnvironment(parsed);
  }

  Future<ImportSummary> _importEnvironment(ParsedPostmanEnvironment parsed) async {
    final taken = {for (final e in await _environmentRepository.watchAll().first) e.name};
    var name = parsed.name;
    for (var n = 1; taken.contains(name); n++) {
      name = n == 1 ? '${parsed.name} (imported)' : '${parsed.name} (imported $n)';
    }
    final environmentId = await _environmentRepository.create(name);
    try {
      for (final variable in parsed.variables) {
        await _environmentRepository.upsertVariable(
          EnvironmentVariableEntity(
            id: 0,
            environmentId: environmentId,
            key: variable.key,
            value: variable.value,
            isSecret: variable.isSecret,
            enabled: variable.enabled,
          ),
        );
      }
    } catch (_) {
      try {
        await _environmentRepository.delete(environmentId);
      } catch (_) {}
      rethrow;
    }
    return ImportSummary(
      format: ImportFormat.postmanEnvironment,
      environments: 1,
      environmentName: name,
      variables: parsed.variables.length,
      skipped: parsed.skipped.length,
      notes: [
        ...parsed.skipped,
        if (parsed.variables.any((v) => !v.enabled)) _disabledNote(parsed),
        if (parsed.variables.any((v) => v.isSecret)) _secretNote(parsed),
      ],
    );
  }

  Future<ImportSummary> _importGlobals(ParsedPostmanEnvironment parsed) async {
    final known = await _globalVariableRepository.watchAll().first;
    final knownKeys = {for (final g in known) g.key};
    final preexistingIds = {for (final g in known) g.id};
    final notes = [...parsed.skipped];
    var added = 0;
    try {
      for (final variable in parsed.variables) {
        if (!knownKeys.add(variable.key)) {
          notes.add('Global variable "${variable.key}" already exists, so its current value was kept.');
          continue;
        }
        await _globalVariableRepository.upsert(
          GlobalVariableEntity(
            id: 0,
            key: variable.key,
            value: variable.value,
            isSecret: variable.isSecret,
            enabled: variable.enabled,
          ),
        );
        added++;
      }
    } catch (_) {
      try {
        for (final global in await _globalVariableRepository.watchAll().first) {
          if (!preexistingIds.contains(global.id)) await _globalVariableRepository.delete(global.id);
        }
      } catch (_) {}
      rethrow;
    }
    return ImportSummary(
      format: ImportFormat.postmanEnvironment,
      globalVariables: added,
      skipped: notes.length,
      notes: [
        ...notes,
        if (parsed.variables.any((v) => !v.enabled)) _disabledNote(parsed),
        if (parsed.variables.any((v) => v.isSecret)) _secretNote(parsed),
      ],
    );
  }

  static String _disabledNote(ParsedPostmanEnvironment parsed) {
    final count = parsed.variables.where((v) => !v.enabled).length;
    final one = count == 1;
    return '$count variable${one ? ' is' : 's are'} disabled, as in the export; switch ${one ? 'it' : 'them'} on to use '
        '${one ? 'it' : 'them'}.';
  }

  static String _secretNote(ParsedPostmanEnvironment parsed) {
    final count = parsed.variables.where((v) => v.isSecret).length;
    return '$count variable${count == 1 ? ' was' : 's were'} marked secret (type "secret", or a name that looks like a '
        'credential).';
  }
}
