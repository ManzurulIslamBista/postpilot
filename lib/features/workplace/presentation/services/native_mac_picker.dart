import 'dart:io';
import 'package:flutter/foundation.dart';

final class NativeMacPicker {
  const NativeMacPicker._();

  /// Prompts the user with the native macOS folder picker sheet / NSOpenPanel.
  static Future<String?> pickFolder({String? initialPath, String prompt = 'Select Workplace Folder'}) async {
    if (!Platform.isMacOS) return null;
    try {
      final script = StringBuffer('POSIX path of (choose folder with prompt "$prompt"');
      if (initialPath != null && initialPath.trim().isNotEmpty && Directory(initialPath.trim()).existsSync()) {
        script.write(' default location POSIX file "${initialPath.trim()}"');
      }
      script.write(')');

      final result = await Process.run('osascript', ['-e', script.toString()]);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        // Remove trailing slash if present for consistency
        return path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
      }
    } catch (e) {
      debugPrint('NativeMacPicker error: $e');
    }
    return null;
  }

  /// Opens the folder in macOS Finder.
  static Future<void> revealInFinder(String folderPath) async {
    if (!Platform.isMacOS) return;
    try {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await Process.run('open', [folderPath]);
    } catch (e) {
      debugPrint('revealInFinder error: $e');
    }
  }
}
