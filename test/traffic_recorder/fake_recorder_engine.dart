// A recorder engine with no socket: it records how it was started and lets a test push finished calls, so the view model and
// the dialog can be tested without a port (and in widget tests, where real sockets are faked away).
import 'dart:async';
import 'package:postpilot/features/traffic_recorder/data/recorder_engine.dart';

final class FakeRecorderEngine implements RecorderEngine {
  bool _running = false;
  int? _port;
  RecorderConfig? _config;
  final _exchanges = StreamController<RecordedExchange>.broadcast();

  int starts = 0;
  int stops = 0;

  /// Set to make the next start fail like a taken port does.
  String? failWith;

  @override
  bool get isRunning => _running;

  @override
  int? get port => _running ? _port : null;

  @override
  RecorderConfig? get config => _config;

  @override
  Stream<RecordedExchange> get exchanges => _exchanges.stream;

  @override
  Future<void> start(RecorderConfig config) async {
    if (failWith != null) throw StateError(failWith!);
    _config = config;
    _port = config.port == 0 ? 49152 : config.port;
    _running = true;
    starts++;
  }

  /// What the app would cause: a call that finished.
  void push(RecordedExchange exchange) => _exchanges.add(exchange);

  @override
  Future<void> stop() async {
    _running = false;
    stops++;
  }

  @override
  Future<void> dispose() async {
    _running = false;
    await _exchanges.close();
  }
}
