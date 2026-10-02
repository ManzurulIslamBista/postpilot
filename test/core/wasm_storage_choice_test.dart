import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/connection/wasm_storage_choice.dart';

/// Which storage the web build picks, including the case that used to fail:
/// shared workers that exist but may not use the network.
void main() {
  const all = [
    WebStorage.opfsShared,
    WebStorage.opfsLocks,
    WebStorage.sharedIndexedDb,
    WebStorage.unsafeIndexedDb,
    WebStorage.inMemory,
  ];

  WebStorage choose(
    List<WebStorage> available, {
    bool sharedUsable = true,
    List<ExistingWebDatabase> existing = const [],
  }) =>
      chooseWebStorage(
        databaseName: 'postpilot',
        available: available,
        existingDatabases: existing,
        sharedWorkersUsable: sharedUsable,
      );

  test('takes the most preferable storage the browser offers, whatever order it lists them in', () {
    expect(choose(all.reversed.toList()), WebStorage.opfsShared);
    expect(
      choose([WebStorage.unsafeIndexedDb, WebStorage.sharedIndexedDb, WebStorage.inMemory]),
      WebStorage.sharedIndexedDb,
    );
  });

  test('skips the shared storages when shared workers cannot reach the network', () {
    final chosen = choose(
      [WebStorage.sharedIndexedDb, WebStorage.unsafeIndexedDb, WebStorage.inMemory],
      sharedUsable: false,
    );

    expect(chosen, WebStorage.unsafeIndexedDb);
    expect(chosen.runsInSharedWorker, isFalse);
  });

  test('an existing IndexedDB database stays readable by the dedicated-worker storage', () {
    final chosen = choose(
      [WebStorage.sharedIndexedDb, WebStorage.unsafeIndexedDb, WebStorage.inMemory],
      sharedUsable: false,
      existing: const [(WebStorageKind.indexedDb, 'postpilot')],
    );

    expect(chosen.kind, WebStorageKind.indexedDb);
  });

  test('an existing database keeps its storage API even when a better one has become available', () {
    final chosen = choose(
      [WebStorage.opfsLocks, WebStorage.unsafeIndexedDb, WebStorage.inMemory],
      existing: const [(WebStorageKind.indexedDb, 'postpilot')],
    );

    expect(chosen, WebStorage.unsafeIndexedDb);
  });

  test('another database in storage does not decide where this one goes', () {
    final chosen = choose(
      [WebStorage.opfsLocks, WebStorage.unsafeIndexedDb, WebStorage.inMemory],
      existing: const [(WebStorageKind.indexedDb, 'some_other_app')],
    );

    expect(chosen, WebStorage.opfsLocks);
  });

  test('falls back to memory when nothing else is usable, instead of throwing', () {
    expect(
      choose([WebStorage.sharedIndexedDb, WebStorage.inMemory], sharedUsable: false),
      WebStorage.inMemory,
    );
    expect(choose(const [], sharedUsable: false), WebStorage.inMemory);
  });
}
