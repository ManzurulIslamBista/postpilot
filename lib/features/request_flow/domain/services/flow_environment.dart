import '../../../../core/utils/variable_resolver.dart';

/// What the flow needs to know about the variables and environment around a request. The app answers from its
/// repositories; a test answers with plain maps.
abstract interface class FlowEnvironment {
  /// The variables a request of [collectionId] (in [folderId]) sees right now, with [dataVariables] (a run's data
  /// row) on top. Asked again whenever a condition is checked, since earlier requests may have saved variables.
  Future<VariableResolver> resolver({required int collectionId, int? folderId, Map<String, String> dataVariables});

  /// The name of the active environment; null for "No Environment".
  Future<String?> environmentName();
}
