/// Where the password of the custom proxy lives: the platform's secure storage,
/// never the settings row in the database (which sits in a synced documents
/// folder on many machines).
abstract interface class ProxyPasswordStore {
  /// The stored password, or an empty string when there is none or the storage
  /// cannot be read.
  Future<String> read();

  /// Stores [password]. False when secure storage refused it: the password is
  /// then held for this session only.
  Future<bool> write(String password);

  Future<void> delete();
}
