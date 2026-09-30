import 'dart:convert';

String relativeTime(DateTime time, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(time);
  if (elapsed.inSeconds < 45) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes < 1 ? 1 : elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
  if (elapsed.inDays == 1) return 'yesterday';
  if (elapsed.inDays < 7) return '${elapsed.inDays} days ago';
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

String formatConflictValue(Object? value, {int maxLength = 160}) {
  if (value == null) return '(not set)';
  final text = value is String ? value : _encode(value);
  if (text.isEmpty) return '(empty)';
  if (text.length <= maxLength) return text;
  var end = maxLength;
  final lastUnit = text.codeUnitAt(end - 1);
  if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF) end--;
  return '${text.substring(0, end)}…';
}

String _encode(Object value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}

String shortSha(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;
