import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The native "choose a folder" dialog and "show in the file manager" for the
/// three desktop platforms. Each shells out to a tool the OS already ships
/// (`osascript`, PowerShell, `zenity`/`kdialog`), so no plugin is needed.
final class DesktopFolderDialogs {
  const DesktopFolderDialogs._();

  static bool get isSupported => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static String get fileManagerName => Platform.isMacOS
      ? 'Finder'
      : Platform.isWindows
          ? 'File Explorer'
          : 'file manager';

  /// The folder the user picked, or null when they cancelled or no chooser is available.
  static Future<String?> pickFolder({String? initialPath, String prompt = 'Select Workplace Folder'}) async {
    final start = _nearestExistingDirectory(initialPath);
    try {
      if (Platform.isMacOS) return await _pickOnMac(prompt, start);
      if (Platform.isWindows) return await _pickOnWindows(prompt, start);
      if (Platform.isLinux) return await _pickOnLinux(prompt, start);
    } catch (e) {
      debugPrint('DesktopFolderDialogs.pickFolder error: $e');
    }
    return null;
  }

  /// Opens [folderPath] in Finder / File Explorer / the default file manager,
  /// creating it first so "Open" never points at nothing.
  static Future<void> reveal(String folderPath) async {
    if (!isSupported) return;
    try {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      if (Platform.isMacOS) {
        await Process.run('open', [folderPath]);
      } else if (Platform.isWindows) {
        // explorer.exe reports exit code 1 even when it opened the folder.
        await Process.run('explorer.exe', [p.normalize(folderPath)]);
      } else {
        await Process.run('xdg-open', [folderPath]);
      }
    } catch (e) {
      debugPrint('DesktopFolderDialogs.reveal error: $e');
    }
  }

  /// [path] or its nearest existing ancestor: a suggested folder that does not
  /// exist yet cannot be a dialog's starting point, but its parent can.
  static String? _nearestExistingDirectory(String? path) {
    var current = path?.trim() ?? '';
    if (current.isEmpty) return null;
    for (var i = 0; i < 32; i++) {
      if (Directory(current).existsSync()) return current;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
    return null;
  }

  static Future<String?> _pickOnMac(String prompt, String? start) async {
    final script = StringBuffer('POSIX path of (choose folder with prompt "${_appleScriptText(prompt)}"');
    if (start != null) script.write(' default location POSIX file "${_appleScriptText(start)}"');
    script.write(')');
    final result = await Process.run('osascript', ['-e', script.toString()]);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    return path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  static Future<String?> _pickOnWindows(String prompt, String? start) async {
    final script = [
      '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding \$false',
      'Add-Type -AssemblyName System.Windows.Forms',
      '[System.Windows.Forms.Application]::EnableVisualStyles()',
      // An invisible always-on-top owner keeps the dialog in front of the app window.
      '\$owner = New-Object System.Windows.Forms.Form',
      '\$owner.TopMost = \$true',
      '\$owner.ShowInTaskbar = \$false',
      '\$dialog = New-Object System.Windows.Forms.FolderBrowserDialog',
      "\$dialog.Description = '${_powerShellText(prompt)}'",
      '\$dialog.ShowNewFolderButton = \$true',
      if (start != null) "\$dialog.SelectedPath = '${_powerShellText(p.normalize(start))}'",
      'if (\$dialog.ShowDialog(\$owner) -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::Out.Write(\$dialog.SelectedPath) }',
    ].join('; ');
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-Command', script],
      stdoutEncoding: utf8,
    );
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  static Future<String?> _pickOnLinux(String prompt, String? start) async {
    final startArg = start == null ? '' : (start.endsWith('/') ? start : '$start/');
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--directory',
        '--title=$prompt',
        if (startArg.isNotEmpty) '--filename=$startArg',
      ]);
      if (result.exitCode != 0) return null;
      final path = (result.stdout as String).trim();
      return path.isEmpty ? null : path;
    } on ProcessException {
      // zenity is not installed (KDE, minimal installs): try kdialog.
    }
    final result = await Process.run('kdialog', [
      '--getexistingdirectory',
      ?start,
      '--title',
      prompt,
    ]);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  static String _appleScriptText(String value) => value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static String _powerShellText(String value) => value.replaceAll("'", "''");
}
