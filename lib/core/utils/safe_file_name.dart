/// Extensions that run code, install software or launch something when the
/// file is opened from a file manager.
const _executableExtensions = <String>{
  'app', 'appref-ms', 'application', 'apk', 'bat', 'cmd', 'com', 'command', 'cpl', 'desktop', 'dll', 'dmg', 'drv',
  'exe', 'gadget', 'hta', 'inf', 'jar', 'js', 'jse', 'lnk', 'msc', 'msi', 'msp', 'pif', 'pkg', 'ps1', 'ps1xml',
  'ps2', 'ps2xml', 'psc1', 'psc2', 'psd1', 'psm1', 'reg', 'scf', 'scr', 'sh', 'sys', 'url', 'vb', 'vbe', 'vbs',
  'ws', 'wsc', 'wsf', 'wsh'
};

const _maxFileNameLength = 150;

// Path separators, characters Windows forbids, control characters, and the
// bidi controls that can make one extension read as another.
final _unsafeChars = RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F\u200E\u200F\u202A-\u202E\u2066-\u2069]+');
final _reservedDeviceName = RegExp(r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$', caseSensitive: false);

bool isExecutableExtension(String extension) => _executableExtensions.contains(extension.toLowerCase());

/// Reduces untrusted text to a single printable path component, or null when
/// nothing usable is left. The extension is not vetted here.
String? sanitizeFileName(String raw) {
  var name = _trimEdges(raw.replaceAll(_unsafeChars, '_'));
  if (name.length > _maxFileNameLength) {
    name = name.substring(0, _maxFileNameLength);
    final last = name.codeUnitAt(name.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) name = name.substring(0, name.length - 1);
    name = _trimEdges(name);
  }
  if (name.isEmpty) return null;
  return _reservedDeviceName.hasMatch(name) ? '_$name' : name;
}

// Leading dots hide a file and Windows silently drops trailing dots and
// spaces. A loop rather than a regex, which takes quadratic time on a long run.
String _trimEdges(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && _isDotOrSpace(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isDotOrSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  return text.substring(start, end);
}

// A dot or any character String.trim() removes.
bool _isDotOrSpace(int unit) =>
    unit == 0x2E ||
    unit <= 0x20 ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000 ||
    unit == 0xFEFF;

/// True when [fileName] is one plain path component that cannot leave the
/// folder it is written to and does not end in an executable extension.
bool isSafeFileName(String fileName) {
  if (fileName.isEmpty || fileName.length > 255) return false;
  if (_unsafeChars.hasMatch(fileName)) return false;
  // Windows silently drops trailing dots and spaces, so "a.exe." becomes "a.exe".
  if (fileName.endsWith('.') || fileName != fileName.trim()) return false;
  final dot = fileName.lastIndexOf('.');
  return dot == -1 || !isExecutableExtension(fileName.substring(dot + 1));
}
