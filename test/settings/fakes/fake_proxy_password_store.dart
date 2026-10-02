import 'package:postpilot/features/settings/domain/repositories/proxy_password_store.dart';

final class FakeProxyPasswordStore implements ProxyPasswordStore {
  FakeProxyPasswordStore([this.stored = '']);

  /// What the "keychain" holds.
  String stored;

  /// While set, [write] refuses like a platform without secure storage.
  bool refuseWrites = false;

  int reads = 0;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String> read() async {
    reads++;
    return stored;
  }

  @override
  Future<bool> write(String password) async {
    writes++;
    if (refuseWrites) return false;
    stored = password;
    return true;
  }

  @override
  Future<void> delete() async {
    deletes++;
    stored = '';
  }
}
