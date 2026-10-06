import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/network/upload_body.dart';

/// A file the user chose. [path] is what the request saves: the path on disk (desktop and mobile), or on the web a
/// [SessionFiles] reference, because a browser hands out no path and cannot read the file again later: the bytes are
/// kept in memory for this session only ([sessionOnly]).
final class PickedFile {
  final String path;
  final String name;
  final int size;
  final bool sessionOnly;

  const PickedFile({required this.path, required this.name, required this.size, required this.sessionOnly});
}

/// The chosen file cannot be used; [message] says why and is shown as it is.
final class FilePickRefused implements Exception {
  final String message;
  const FilePickRefused(this.message);

  @override
  String toString() => message;
}

abstract interface class FilePickerService {
  /// Opens the system file dialog. Null when the user closed it without choosing.
  Future<PickedFile?> pick();
}

/// The official `file_selector` plugin (Windows, macOS, Linux, Android, iOS and the web).
///
/// On desktop and mobile the path of the chosen file is what is saved. On the web there is no path, so the bytes are
/// read once and kept in memory for the session; [isWeb] and [open] are replaced in tests to run both branches.
final class FileSelectorPicker implements FilePickerService {
  final SessionFiles _sessionFiles;
  final bool _isWeb;
  final Future<XFile?> Function() _open;

  FileSelectorPicker({SessionFiles? sessionFiles, bool? isWeb, Future<XFile?> Function()? open})
      : _sessionFiles = sessionFiles ?? SessionFiles.shared,
        _isWeb = isWeb ?? kIsWeb,
        _open = open ?? openFile;

  @override
  Future<PickedFile?> pick() async {
    final file = await _open();
    if (file == null) return null;
    final size = await file.length();
    if (!_isWeb) return PickedFile(path: file.path, name: file.name, size: size, sessionOnly: false);

    if (size > UploadLimits.webSessionBytes) {
      throw FilePickRefused(
        '"${file.name}" is ${UploadLimits.describe(size)}. A browser keeps the file in memory while it is sent, '
        'so the web version takes files up to ${UploadLimits.describe(UploadLimits.webSessionBytes)}: '
        'use the desktop app for a larger one.',
      );
    }
    final reference = _sessionFiles.add(name: file.name, bytes: await file.readAsBytes());
    return PickedFile(path: reference, name: file.name, size: size, sessionOnly: true);
  }
}
