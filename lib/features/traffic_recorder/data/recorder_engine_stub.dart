import 'recorder_engine.dart';

bool get isRecorderSupported => false;

RecorderEngine createRecorderEngine() => throw UnsupportedError('A traffic recorder needs a platform that can listen on a port.');
