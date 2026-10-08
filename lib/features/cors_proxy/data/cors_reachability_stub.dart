/// Whether something answers at [url], whatever it answers: true, false, or null when this platform cannot tell. Outside a
/// browser a refused connection is told by its own error, so there is nothing to find out.
Future<bool?> probeReachable(Uri url) async => null;

/// The address of the page the app runs in (`https://app.example.com`), null outside a browser.
String? currentPageOrigin() => null;
