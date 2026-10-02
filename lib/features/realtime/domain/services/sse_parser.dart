/// One Server-Sent Event, as the stream delivers it.
final class SseEvent {
  /// `message` unless the server named the event.
  final String event;
  final String data;
  final String? id;
  final int? retryMs;

  const SseEvent({required this.event, required this.data, this.id, this.retryMs});
}

/// Reads a `text/event-stream` as it arrives in arbitrary chunks. Follows the
/// WHATWG rules: fields are `event`, `data`, `id` and `retry`, a line starting
/// with `:` is a comment, `\n`, `\r` and `\r\n` all end a line, several `data`
/// lines are joined with newlines, and a blank line sends the event.
final class SseParser {
  String _buffer = '';

  /// The last chunk ended with a CR, so an LF opening the next one belongs to it (CRLF split across chunks).
  bool _afterCr = false;
  String _event = '';
  final List<String> _data = [];
  String? _id;
  int? _retry;

  /// Feeds [chunk] and returns the events that were completed by it.
  List<SseEvent> add(String chunk) {
    if (_afterCr && chunk.startsWith('\n')) chunk = chunk.substring(1);
    if (chunk.isNotEmpty) _afterCr = false;
    _buffer += chunk;
    final events = <SseEvent>[];
    while (true) {
      final end = _lineEnd(_buffer);
      if (end == null) break;
      final line = _buffer.substring(0, end.$1);
      _afterCr = _buffer.codeUnitAt(end.$1) == 0x0D && end.$2 == _buffer.length;
      _buffer = _buffer.substring(end.$2);
      final event = _line(line);
      if (event != null) events.add(event);
    }
    return events;
  }

  /// (index where the line text ends, index where the next line starts), or
  /// null when no complete line is buffered. A CR ending the buffer ends the
  /// line at once; [_afterCr] then swallows the LF if one opens the next chunk.
  (int, int)? _lineEnd(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x0A) return (i, i + 1);
      if (c == 0x0D) return (i, i + 1 < s.length && s.codeUnitAt(i + 1) == 0x0A ? i + 2 : i + 1);
    }
    return null;
  }

  SseEvent? _line(String line) {
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        _data.add(value);
      case 'id':
        if (!value.contains('\u0000')) _id = value;
      case 'retry':
        _retry = int.tryParse(value) ?? _retry;
    }
    return null;
  }

  SseEvent? _dispatch() {
    if (_data.isEmpty) {
      _event = '';
      return null;
    }
    final event = SseEvent(event: _event.isEmpty ? 'message' : _event, data: _data.join('\n'), id: _id, retryMs: _retry);
    _event = '';
    _data.clear();
    _retry = null;
    return event;
  }
}
