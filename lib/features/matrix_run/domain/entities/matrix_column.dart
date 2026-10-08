import 'matrix_identity.dart';

/// One column of a matrix run: an environment (by name) and/or an identity. A column without an environment uses
/// whatever environment is active when the run starts.
final class MatrixColumn {
  /// The environment's name; null keeps the active environment.
  final String? environment;
  final MatrixIdentity? identity;

  const MatrixColumn({this.environment, this.identity});

  /// Stable within one run, so expectations and cells can be found again: the environment and the identity's id.
  String get key => '${environment ?? ''}|${identity?.id ?? ''}';

  /// `Staging · admin`, `Staging`, `admin` or `Active environment`.
  String get label {
    final parts = [?environment, ?identity?.name];
    return parts.isEmpty ? 'Active environment' : parts.join(' · ');
  }

  /// The variables put on top of the environment for this column.
  Map<String, String> get overrides => identity?.variables ?? const {};

  /// Every environment with every identity, environment by environment (`Dev · admin`, `Dev · user`, `Prod · admin`
  /// ...). Without identities a column is just the environment, without environments just the identity in the active
  /// environment; with neither there is nothing to compare.
  static List<MatrixColumn> product(List<String> environments, List<MatrixIdentity> identities) {
    if (environments.isEmpty) return [for (final i in identities) MatrixColumn(identity: i)];
    if (identities.isEmpty) return [for (final e in environments) MatrixColumn(environment: e)];
    return [
      for (final e in environments)
        for (final i in identities) MatrixColumn(environment: e, identity: i),
    ];
  }

  @override
  bool operator ==(Object other) => other is MatrixColumn && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
