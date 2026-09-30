import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/environment_entity.dart';
import '../../domain/entities/global_variable_entity.dart';
import '../../domain/repositories/environment_repository.dart';
import '../../domain/repositories/global_variable_repository.dart';

final class EnvironmentsViewModel with ChangeNotifier {
  final EnvironmentRepository _environmentRepository;
  final GlobalVariableRepository _globalVariableRepository;

  EnvironmentsViewModel(this._environmentRepository, this._globalVariableRepository) {
    _environmentsSub = _environmentRepository.watchAll().listen((value) {
      environments = value;
      notifyListeners();
    });
  }

  List<EnvironmentEntity> environments = [];
  late final StreamSubscription<List<EnvironmentEntity>> _environmentsSub;

  final Map<int, List<EnvironmentVariableEntity>> _variablesByEnvironment = {};
  final Map<int, StreamSubscription<List<EnvironmentVariableEntity>>> _variableSubs = {};

  List<GlobalVariableEntity> globals = [];
  StreamSubscription<List<GlobalVariableEntity>>? _globalsSub;

  List<EnvironmentVariableEntity> variablesFor(int environmentId) => _variablesByEnvironment[environmentId] ?? const [];

  void watchVariables(int environmentId) {
    if (_variableSubs.containsKey(environmentId)) return;
    _variableSubs[environmentId] = _environmentRepository.watchVariables(environmentId).listen((value) {
      _variablesByEnvironment[environmentId] = value;
      notifyListeners();
    });
  }

  void watchGlobals() {
    if (_globalsSub != null) return;
    _globalsSub = _globalVariableRepository.watchAll().listen((value) {
      globals = value;
      notifyListeners();
    });
  }

  Future<void> createEnvironment(String name) => _environmentRepository.create(name);
  Future<void> renameEnvironment(int id, String name) => _environmentRepository.rename(id, name);
  Future<void> setActive(int id) => _environmentRepository.setActive(id);
  Future<void> clearActive() => _environmentRepository.clearActive();
  Future<void> deleteEnvironment(int id) => _environmentRepository.delete(id);
  Future<void> upsertVariable(EnvironmentVariableEntity variable) => _environmentRepository.upsertVariable(variable);
  Future<void> deleteVariable(int id) => _environmentRepository.deleteVariable(id);
  Future<void> upsertGlobal(GlobalVariableEntity variable) => _globalVariableRepository.upsert(variable);
  Future<void> deleteGlobal(int id) => _globalVariableRepository.delete(id);

  @override
  void dispose() {
    _environmentsSub.cancel();
    _globalsSub?.cancel();
    for (final sub in _variableSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
