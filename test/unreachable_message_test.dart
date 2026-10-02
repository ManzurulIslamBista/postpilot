import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/errors/unreachable_message.dart';

void main() {
  test('desktop and mobile get the plain wording', () {
    expect(unreachableServerMessage(web: false), "Couldn't reach the server — check the URL and your connection");
  });

  test('in a browser the message also names CORS, so a refusal is not mistaken for a bad URL', () {
    final message = unreachableServerMessage(web: true);

    expect(message, startsWith("Couldn't reach the server — check the URL and your connection"));
    expect(message, contains('CORS'));
    expect(message, contains('desktop and mobile apps'));
  });
}
