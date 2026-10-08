import '../entities/matrix_identity.dart';

/// Where the identities of a workplace are kept between sessions. Per device: the values are tokens and passwords, so
/// they stay on this computer and never go into `workspace.json`, Git or a backup.
abstract interface class MatrixIdentityStore {
  /// The saved identities; empty when there are none or the saved value cannot be read.
  Future<List<MatrixIdentity>> load();

  Future<void> save(List<MatrixIdentity> identities);
}
