/// Line rules shared by the parser and by code that has to leave fenced code
/// alone, so both agree on where a fence starts and ends.
abstract final class MarkdownLines {
  static final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');

  /// The fence [line] opens, or null. A backtick fence's info string cannot
  /// hold a backtick, which keeps "```code```" an inline code span.
  static ({String char, int length, String info})? fenceOpen(String line) {
    final match = _fence.firstMatch(line);
    if (match == null) return null;
    final marker = match[1]!;
    final info = match[2]!.trim();
    if (marker[0] == '`' && info.contains('`')) return null;
    return (char: marker[0], length: marker.length, info: info);
  }

  static bool isFenceClose(String line, String char, int length) {
    var i = 0;
    while (i < line.length && i < 4 && line[i] == ' ') {
      i++;
    }
    if (i > 3) return false;
    var run = 0;
    while (i < line.length && line[i] == char) {
      i++;
      run++;
    }
    return run >= length && line.substring(i).trim().isEmpty;
  }
}
