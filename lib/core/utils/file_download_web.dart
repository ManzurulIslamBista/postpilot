import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external _Blob(JSArray<JSUint8Array> parts, JSObject options);
}

extension type _AnchorElement._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

@JS('document.createElement')
external _AnchorElement _createElement(String tagName);

@JS('URL.createObjectURL')
external String _createObjectUrl(JSObject blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

Future<String?> downloadFile({required String fileName, required Uint8List bytes, required String mimeType}) async {
  final blob = _Blob([bytes.toJS].toJS, {'type': mimeType}.jsify() as JSObject);
  final url = _createObjectUrl(blob);
  _createElement('a')
    ..href = url
    ..download = fileName
    ..click();
  // The browser reads the blob asynchronously once the click starts the
  // download, so revoking immediately can abort it.
  Timer(const Duration(seconds: 10), () => _revokeObjectUrl(url));
  return null;
}
