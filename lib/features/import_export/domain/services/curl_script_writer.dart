/// One request of an exported cURL script. Exactly one of [command] and
/// [failure] is set.
final class CurlScriptEntry {
  final String name;

  /// "Parent / Child" path of the folder the request is in; null at the top level.
  final String? folder;
  final String? command;

  /// Why no command could be generated for this request.
  final String? failure;

  const CurlScriptEntry.generated({required this.name, required this.folder, required String this.command}) : failure = null;

  const CurlScriptEntry.failed({required this.name, required this.folder, required String this.failure}) : command = null;
}

/// Lays out generated `curl` commands as one shell script: a comment naming
/// the collection, a banner per folder, and each request's name as a comment
/// right above its command (which is what `CurlScriptParser` reads back as the
/// request name).
abstract final class CurlScriptWriter {
  static String write({required String collectionName, required List<CurlScriptEntry> entries}) {
    final lines = [
      '#!/usr/bin/env bash',
      '# PostPilot collection: ${_oneLine(collectionName, 'Untitled collection')}',
      '# Variables and secrets are written with the values they have right now, in plain text.',
    ];
    String? previousFolder;
    for (final entry in entries) {
      if (entry.folder != previousFolder) {
        lines.addAll(['', '# --- ${entry.folder ?? 'Collection root'} ---']);
        previousFolder = entry.folder;
      }
      lines.addAll(['', '# ${_oneLine(entry.name, 'Untitled request')}']);
      final failure = entry.failure;
      if (failure != null) {
        lines.add('# Could not generate a command for this request: ${_oneLine(failure, 'unknown error')}');
      } else {
        lines.add(entry.command!);
      }
    }
    return '${lines.join('\n')}\n';
  }

  /// A comment ends at the newline, so a name holding one would spill into a command.
  static String _oneLine(String text, String fallback) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.isEmpty ? fallback : collapsed;
  }
}
