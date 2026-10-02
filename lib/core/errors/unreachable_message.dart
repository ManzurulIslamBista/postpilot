import 'package:flutter/foundation.dart';

/// What to tell the user when a request never got an answer.
///
/// In a browser that is not always a bad URL or a lost connection: a page can
/// only call servers that explicitly allow its origin (CORS), and a refusal looks
/// exactly like "unreachable" to the page. Saying so saves a long hunt for a
/// problem that is not there; the desktop and mobile apps have no such limit.
String unreachableServerMessage({bool web = kIsWeb}) {
  const base = "Couldn't reach the server — check the URL and your connection";
  if (!web) return base;
  return "$base. In a browser this also happens when the server doesn't allow requests from web pages (CORS); "
      "the desktop and mobile apps aren't limited that way.";
}
