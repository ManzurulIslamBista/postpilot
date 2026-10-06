import 'dart:async';
import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';
import '../entities/variable_info.dart';

/// Every `{{variable}}` a request in [collectionId] can see, with where each
/// one comes from. Layered exactly as [BuildVariableResolverUseCase] resolves
/// them (active environment > collection > globals): a name held by several
/// scopes appears once, as the highest-precedence scope's. Disabled variables
/// are not visible to a request, so they are left out.
final class ListVariablesUseCase implements UseCase<Map<String, VariableInfo>, int> {
  final CollectionVariableRepository _collectionVariables;
  final EnvironmentRepository _environments;
  final GlobalVariableRepository _globals;

  const ListVariablesUseCase(this._collectionVariables, this._environments, this._globals);

  /// Fires whenever what [call] returns for [collectionId] may have changed: a
  /// global or collection variable is added, edited, toggled or deleted, a
  /// different environment becomes active (or none), or a variable of the
  /// active environment changes. A listener also gets one event per source as
  /// the database streams deliver their current rows, so it should coalesce.
  ///
  /// Watching the repositories rather than a view model is what keeps the
  /// colouring of `{{tokens}}` right in every case: a variable a script just
  /// extracted, one edited in the collection's settings, one typed into the
  /// environments dialog, wherever the change came from.
  Stream<void> changes(int collectionId) {
    final subscriptions = <StreamSubscription<Object?>>[];
    StreamSubscription<Object?>? activeVariables;
    int? activeId;
    late final StreamController<void> controller;

    void ping() {
      if (!controller.isClosed) controller.add(null);
    }

    // A source that cannot be watched is skipped: the colouring is a convenience.
    StreamSubscription<Object?>? watch<T>(Stream<T> Function() open, void Function(T) onData) {
      try {
        return open().listen(onData, onError: (_) {});
      } catch (_) {
        return null;
      }
    }

    controller = StreamController<void>(
      onListen: () {
        final sources = [
          watch(_globals.watchAll, (_) => ping()),
          watch(() => _collectionVariables.watchByCollection(collectionId), (_) => ping()),
          watch(_environments.watchAll, (environments) {
            final id = environments.where((e) => e.isActive).firstOrNull?.id;
            if (id != activeId) {
              activeId = id;
              activeVariables?.cancel();
              activeVariables = id == null ? null : watch(() => _environments.watchVariables(id), (_) => ping());
            }
            ping();
          }),
        ];
        subscriptions.addAll(sources.nonNulls);
      },
      onCancel: () async {
        await Future.wait([for (final s in subscriptions) s.cancel(), ?activeVariables?.cancel()]);
      },
    );
    return controller.stream;
  }

  @override
  Future<Map<String, VariableInfo>> call(int collectionId) async {
    final result = <String, VariableInfo>{};

    // Lowest precedence first, so each later scope overwrites the one below.
    for (final g in await _globals.watchAll().first) {
      if (!g.enabled) continue;
      result[g.key] = VariableInfo(
        name: g.key,
        source: VariableSource.global,
        value: g.value,
        isSecret: g.isSecret,
      );
    }
    for (final v in await _collectionVariables.watchByCollection(collectionId).first) {
      if (!v.enabled) continue;
      result[v.key] = VariableInfo(name: v.key, source: VariableSource.collection, value: v.value);
    }
    final active = (await _environments.watchAll().first).where((e) => e.isActive).firstOrNull;
    if (active != null) {
      for (final v in await _environments.watchVariables(active.id).first) {
        if (!v.enabled) continue;
        result[v.key] = VariableInfo(
          name: v.key,
          source: VariableSource.environment,
          scopeName: active.name,
          value: v.value,
          isSecret: v.isSecret,
        );
      }
    }
    return result;
  }
}
