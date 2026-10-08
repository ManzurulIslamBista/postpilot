import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Whether something answers at [url], whatever it answers. A browser reports a server that is down and one that did not
/// allow this page as the same opaque error; a `no-cors` request tells them apart, because it succeeds (with an answer the
/// page cannot read) whenever a server is there.
Future<bool?> probeReachable(Uri url) async {
  try {
    await web.window
        .fetch(url.toString().toJS, web.RequestInit(mode: 'no-cors', cache: 'no-store'))
        .toDart
        .timeout(const Duration(seconds: 6));
    return true;
  } catch (_) {
    return false;
  }
}

/// The address of the page the app runs in (`https://app.example.com`).
String? currentPageOrigin() {
  final origin = web.window.location.origin;
  return origin.startsWith('http') ? origin : null;
}
