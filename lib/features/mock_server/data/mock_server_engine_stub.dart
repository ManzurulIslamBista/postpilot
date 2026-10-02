import 'mock_server_engine.dart';

bool get isMockServerSupported => false;

MockServerEngine createMockServerEngine() => throw UnsupportedError('A mock server needs a platform that can listen on a port.');
