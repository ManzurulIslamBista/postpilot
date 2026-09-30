import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/request_builder/domain/services/jwt_signer.dart';

void main() {
  // Payload key order matters: JWT signs the literal JSON bytes, and this
  // order matches jwt.io's canonical HS256 example so the expected tokens
  // below (independently recomputed with Python's hmac/hashlib, not from
  // memory) are byte-exact, not just "looks like a JWT".
  const payload = {'sub': '1234567890', 'name': 'John Doe', 'iat': 1516239022};
  const secret = 'your-256-bit-secret';

  test('HS256 matches the reference token exactly', () {
    final token = JwtSigner.sign(secret: secret, algorithm: JwtAlgorithm.hs256, payload: payload);
    expect(
      token,
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
      'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c',
    );
  });

  test('HS384 matches the reference token exactly', () {
    final token = JwtSigner.sign(secret: secret, algorithm: JwtAlgorithm.hs384, payload: payload);
    expect(
      token,
      'eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.'
      'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
      'RGFdh_VuEuURSubru7xP4rbaA4boUyueI7rEm75l1cNdE9gQ7H6mx2DYpauBjX5S',
    );
  });

  test('HS512 matches the reference token exactly', () {
    final token = JwtSigner.sign(secret: secret, algorithm: JwtAlgorithm.hs512, payload: payload);
    expect(
      token,
      'eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.'
      'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
      'pazba9Pj009HgANP4pTCQAHpXNU7pVbjIGff_plktSzsa9rXTGzFngaawzXGEO6Q0Hx5dtGi-dMDlIadV81o3Q',
    );
  });

  test('base64url output has no padding and no +/ characters', () {
    final token = JwtSigner.sign(secret: secret, algorithm: JwtAlgorithm.hs256, payload: payload);
    expect(token, isNot(contains('=')));
    expect(token, isNot(contains('+')));
    expect(token, isNot(contains('/')));
  });

  test('a different secret produces a different signature', () {
    final a = JwtSigner.sign(secret: secret, algorithm: JwtAlgorithm.hs256, payload: payload);
    final b = JwtSigner.sign(secret: 'wrong-secret', algorithm: JwtAlgorithm.hs256, payload: payload);
    expect(a, isNot(b));
  });
}
