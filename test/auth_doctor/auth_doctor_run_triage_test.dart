// The 401/403 doctor inside the run triage: a rejected group's hint keeps its words, and gets the doctor's top finding after them when
// that finding is more than a hedge. A run record keeps no headers and no body, so the doctor can only use the status, the host, the
// environment and how the rest of the run fared on the same host.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/run_triage/domain/entities/run_record_doc.dart';
import 'package:postpilot/features/run_triage/domain/services/failure_triage.dart';
import '../run_triage/run_fixtures.dart';

const _expiredToken =
    '{n} failed with 401 (Unauthorized): the token or API key was probably rejected or has expired. '
    'Renew the auth (or run the login request again) and re-run the failed requests.';

String _hint(List<RunResultEntry> results, {String environment = ''}) =>
    FailureTriage.analyse(results, environment: environment).groups.first.hint;

void main() {
  test('when other requests to the host passed, the doctor only hedges, so the hint is exactly what it always was', () {
    final results = [
      for (var i = 1; i <= 12; i++) failedWith('Rejected $i', 401),
      for (var i = 1; i <= 68; i++) entry('Passing $i'),
    ];

    expect(_hint(results), _expiredToken.replaceFirst('{n}', '12 requests'));
  });

  test('when nothing to the host got through, the doctor says that the credential as a whole is the suspect', () {
    final results = [for (var i = 1; i <= 5; i++) failedWith('Rejected $i', 401)];

    final hint = _hint(results);

    expect(hint, startsWith(_expiredToken.replaceFirst('{n}', '5 requests')));
    expect(hint, contains('Not one request to api.shop.test got through, so one credential is the problem'));
    expect(hint, endsWith('check the active environment, and re-run.'));
  });

  test('only the requests to the same host count as having got through', () {
    final results = [
      for (var i = 1; i <= 3; i++) failedWith('Rejected $i', 401),
      for (var i = 1; i <= 9; i++) entry('Elsewhere $i', url: 'https://other.shop.test/ok-$i'),
    ];

    expect(_hint(results), contains('Not one request to api.shop.test got through'));
  });

  test('the environment of the run lets the doctor see a production host reached with a staging environment', () {
    final results = [entry('Login', url: 'https://prod.shop.test/login', status: 401, passed: false)];

    final inStaging = _hint(results, environment: 'Staging');
    final without = _hint(results);

    expect(inStaging, startsWith(_expiredToken.replaceFirst('{n}', '1 request')));
    expect(inStaging, contains('looks like production, while the active environment "Staging" looks like staging or development'));
    expect(without, _expiredToken.replaceFirst('{n}', '1 request'));
  });

  test('403 gets the doctor\'s words for the user as a whole', () {
    final results = [for (var i = 1; i <= 4; i++) failedWith('Forbidden $i', 403)];

    final hint = _hint(results);

    expect(hint, startsWith('4 requests failed with 403 (Forbidden): the credentials were accepted but are not allowed to do this.'));
    expect(hint, contains('the user as a whole is refused'));
  });

  test('a single rejected request proves nothing more, and a failure that is not a rejection is untouched', () {
    expect(_hint([failedWith('One', 401)]), _expiredToken.replaceFirst('{n}', '1 request'));
    expect(_hint([failedWith('One', 404)]), isNot(contains('credential')));
    expect(_hint([entry('Slow', status: null, passed: false, error: 'The server at db.shop.test did not answer within 30 seconds.')]), contains('timed out waiting for db.shop.test'));
  });

  test('a renewal that failed has no status, so the doctor adds nothing to it', () {
    final results = [entry('Needs token', status: null, passed: false, error: 'The access token could not be renewed. The request was not sent: check the OAuth settings.')];

    final hint = _hint(results);

    expect(hint, contains('could not be sent because the access token could not be renewed'));
    expect(hint, isNot(contains('Not one request')));
  });
}
