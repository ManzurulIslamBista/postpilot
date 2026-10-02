import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'wasm_storage_choice.dart';

const _databaseName = 'postpilot';

// `sqlite3.wasm` and `drift_worker.js` live in web/ (see web/drift_worker.dart
// for the worker source; recompile it with `dart compile js` if it changes).
final _sqlite3Uri = Uri.parse('sqlite3.wasm');
final _driftWorkerUri = Uri.parse('drift_worker.js');

/// SQLite compiled to WebAssembly, stored in the browser.
///
/// Opens the way `driftDatabase` does, except that it first checks the one thing
/// drift's own feature detection cannot see: whether a shared worker is
/// actually allowed to download `sqlite3.wasm`. Where it is not, the shared
/// storages are skipped and a dedicated worker hosts the database, instead of
/// every query failing with "TypeError: Failed to fetch".
QueryExecutor openAppConnection() => DatabaseConnection.delayed(Future(_open));

Future<DatabaseConnection> _open() async {
  final probed = await WasmDatabase.probe(
    sqlite3Uri: _sqlite3Uri,
    driftWorkerUri: _driftWorkerUri,
    databaseName: _databaseName,
  );

  final sharedUsable = await _sharedWorkerCanFetch(_sqlite3Uri);
  final storage = chooseWebStorage(
    databaseName: _databaseName,
    available: [for (final s in probed.availableStorages) ?_byName(WebStorage.values, s.name)],
    existingDatabases: [
      for (final (api, name) in probed.existingDatabases)
        if (_byName(WebStorageKind.values, api.name) case final kind?) (kind, name),
    ],
    sharedWorkersUsable: sharedUsable,
  );
  final implementation = WasmStorageImplementation.values.byName(storage.name);

  if (!sharedUsable) {
    debugPrint(
      'PostPilot: this browser blocks network access from shared workers; storing the database with ${storage.name} instead.',
    );
  }
  if (storage == WebStorage.inMemory) {
    debugPrint('PostPilot: no persistent storage is available here; data will be lost when the page is closed.');
  }
  return probed.open(implementation, _databaseName);
}

/// The value of [values] called [name], or null for one this app does not know
/// (a storage a future drift adds), which is then simply never chosen.
T? _byName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// Starts a throwaway shared worker that fetches [resource], and reports
/// whether that worked. Anything unexpected counts as "not usable", which only
/// costs the (equally capable) dedicated-worker storage.
Future<bool> _sharedWorkerCanFetch(Uri resource) async {
  if (!globalContext.has('SharedWorker')) {
    return true; // No shared storage is offered then.
  }

  final url = Uri.base.resolveUri(resource).toString();
  final script =
      '''
self.onconnect = (event) => {
  const port = event.ports[0];
  const controller = new AbortController();
  fetch(${jsonEncode(url)}, { signal: controller.signal })
    .then((response) => { controller.abort(); port.postMessage(response.ok); })
    .catch(() => port.postMessage(false));
};
''';

  final blob = web.Blob([script.toJS].toJS, web.BlobPropertyBag(type: 'text/javascript'));
  final scriptUrl = web.URL.createObjectURL(blob);
  web.SharedWorker? worker;
  final result = Completer<bool>();
  try {
    worker = web.SharedWorker(scriptUrl.toJS, 'postpilot network probe'.toJS);
    worker.onerror = ((web.Event _) {
      if (!result.isCompleted) result.complete(false);
    }).toJS;
    worker.port.onmessage = ((web.MessageEvent event) {
      if (result.isCompleted) return;
      final data = event.data;
      result.complete(data.isA<JSBoolean>() && (data as JSBoolean).toDart);
    }).toJS;
    worker.port.start();
    return await result.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
  } catch (_) {
    return false;
  } finally {
    worker?.port.close();
    web.URL.revokeObjectURL(scriptUrl);
  }
}
