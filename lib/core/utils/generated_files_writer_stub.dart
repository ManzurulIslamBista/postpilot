bool get canWriteFilesToFolder => false;

Future<int> writeFilesToFolder(String folder, Map<String, String> files) =>
    throw UnsupportedError('Writing to a folder is not supported on this platform');
