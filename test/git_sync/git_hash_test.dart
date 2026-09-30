import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/git_hash.dart';

// Expected values come from `git hash-object --stdin`.
void main() {
  test('empty text is the well-known empty blob', () {
    expect(GitHash.blobSha(''), 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391');
  });

  test('matches git for "hello\\n"', () {
    expect(GitHash.blobSha('hello\n'), 'ce013625030ba8dba906f756967f9e9ca394464a');
  });

  test('a missing trailing newline changes the sha', () {
    expect(GitHash.blobSha('hello'), 'b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0');
  });

  test('the length in the header counts UTF-8 bytes, not characters', () {
    expect(GitHash.blobSha('héllo বাং\n'), '3b2ce00839285ef0d459e7e64c8f8cec5c59c4fe');
  });

  test('canonical JSON text hashes like the file a push writes', () {
    expect(GitHash.blobSha(canonicalJson({'a': 1})), '8d6b85c7b3f97652ab7fdfdf53f3dd2b6dc3ccef');
  });

  test('the same text always gives the same sha', () {
    expect(GitHash.blobSha('same'), GitHash.blobSha('same'));
    expect(GitHash.blobSha('same'), isNot(GitHash.blobSha('same ')));
  });
}
