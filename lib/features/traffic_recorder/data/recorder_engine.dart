// Pure Dart plus a conditional import (like the mock server's engine): nothing here needs Flutter, so a tiny script can
// `import` this file, call `RecorderEngine.create().start(...)` and listen to `exchanges`.
import 'recorder_config.dart';
import '../domain/entities/recorded_exchange.dart';
import 'recorder_engine_stub.dart' if (dart.library.io) 'recorder_engine_io.dart' as platform;

export 'recorder_config.dart';
export '../domain/entities/recorded_exchange.dart';

/// A reverse proxy that records. The app talks to it as if it were the server (its base URL is the recorder's address); every
/// call is forwarded to [RecorderConfig.upstream], the answer is streamed back unchanged, and a copy of the exchange is
/// published on [exchanges]. No certificate, no system proxy setting.
abstract interface class RecorderEngine {
  /// False in a browser, which cannot listen on a port.
  static bool get isSupported => platform.isRecorderSupported;
  static RecorderEngine create() => platform.createRecorderEngine();

  bool get isRunning;

  /// The port it listens on (the real one when 0 was asked for); null when stopped.
  int? get port;

  /// What it was started with; null before the first start.
  RecorderConfig? get config;

  /// Every finished call, in the order they finished. A broadcast stream.
  Stream<RecordedExchange> get exchanges;

  /// Starts listening. Throws a [StateError] with a readable message when the port is taken or the configuration is wrong.
  Future<void> start(RecorderConfig config);

  /// Stops listening and drops the calls still in flight.
  Future<void> stop();
  Future<void> dispose();
}
