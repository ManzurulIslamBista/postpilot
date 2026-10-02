// The database connection for the platform this build runs on: SQLite files
// through `dart:io` natively, and a resilient WebAssembly SQLite in the browser.
export 'app_connection_web.dart' if (dart.library.io) 'app_connection_native.dart';
