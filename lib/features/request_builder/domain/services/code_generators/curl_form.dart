/// The value of a `curl --form name=<value>` option that sends a file: `@path`, then `;type=` and `;filename=` when
/// they are given. The one place that writes it, so the cURL snippet, the History "Copy as cURL" and the exported
/// cURL script all say a file the same way, and `CurlParser` reads exactly this back.
///
/// curl splits the value at `;` and `,` and reads a double quote as the start of a quoted name, so a path with one
/// of those is written in double quotes (with `\"` and `\\` escaped), as `curl --help` describes.
String curlFileFormValue(String path, {String? contentType, String? fileName}) {
  final buffer = StringBuffer('@${_curlFormName(path)}');
  if (contentType != null && contentType.isNotEmpty) buffer.write(';type=$contentType');
  if (fileName != null && fileName.isNotEmpty) buffer.write(';filename=${_curlFormName(fileName)}');
  return buffer.toString();
}

String _curlFormName(String name) {
  if (!name.contains(RegExp(r'[;,"]'))) return name;
  return '"${name.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
