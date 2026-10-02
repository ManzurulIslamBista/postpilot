// The storage for the platform this build runs on: real files wherever
// `dart:io` exists, browser storage on the web (where importing `dart:io`
// code would throw at runtime).
export 'workplace_storage_factory_web.dart' if (dart.library.io) 'workplace_storage_factory_io.dart';
