// Cron expressions as GitHub Actions reads them. The expectations are worked out from the cron rules, not from the code:
// five fields, ranges 0-59 / 0-23 / 1-31 / 1-12 / 0-6, and a gap of at least five minutes between two runs.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/ci/domain/services/cron_validator.dart';

void main() {
  group('valid schedules', () {
    for (final cron in const [
      '17 6 * * *', // every day at 06:17
      '*/15 * * * *', // every quarter of an hour
      '*/5 * * * *', // exactly the five-minute limit
      '0 0 * * 1-5', // weekdays at midnight
      '5,35 8-18 * * MON-FRI', // twice an hour in office hours, weekday names
      '0 0 1 JAN *', // 1 January, month name
      '0 12 29 2 *', // 29 February exists (leap years)
      '0 0,12 * * *', // two runs twelve hours apart
      '59 23 * * 0', // once a week, Sunday as 0
      '10-50/10 * * * *', // 10, 20, 30, 40, 50: ten minutes apart
      '57,3 * * * *', // 3 and 57: 54 and 6 minutes apart
      '58,3 * * * *', // 58 -> 3 next hour is exactly 5 minutes
      '  17   6 * *   *  ', // spaces around the fields are fine
    ]) {
      test('"$cron"', () => expect(CronValidator.validate(cron), isNull));
    }
  });

  group('invalid schedules say what to change', () {
    final cases = <String, String>{
      '': 'Enter a cron expression',
      '   ': 'Enter a cron expression',
      '@daily': 'does not understand "@daily"',
      '* * * *': 'five fields',
      '* * * * * *': 'five fields',
      '60 * * * *': 'minute field takes a number from 0 to 59',
      '* 24 * * *': 'hour field takes a number from 0 to 23',
      '0 0 32 * *': 'day of month field takes a number from 1 to 31',
      '0 0 0 * *': 'day of month field takes a number from 1 to 31',
      '0 0 * 13 *': 'month field takes a number from 1 to 12',
      '0 0 * * 7': 'Sunday is 0',
      '0 0 * * ABC': 'day of week field takes',
      'x * * * *': 'minute field takes',
      '1/0 * * * *': 'must be a whole number from 1',
      '5-1 * * * *': 'goes backwards',
      '1,,3 * * * *': 'empty entry',
      '* * * * *': 'every 1 minute',
      '*/2 * * * *': 'every 2 minutes',
      '0,3 * * * *': 'every 3 minutes',
      '58,2 * * * *': 'every 4 minutes', // 58 -> 02 of the next hour
      '0 0 31 2 *': 'never occur together',
    };
    cases.forEach((cron, fragment) {
      test('"$cron"', () {
        final message = CronValidator.validate(cron);
        expect(message, isNotNull);
        expect(message, contains(fragment));
        expect(CronValidator.isValid(cron), isFalse);
      });
    });
  });

  test('a day that exists in another listed month is accepted', () {
    // 31 does not exist in February but does in January.
    expect(CronValidator.validate('0 0 31 1,2 *'), isNull);
  });

  test('the day of week keeps a restricted day of month usable', () {
    // With a weekday given, cron runs when either matches, so 31 February is not a dead schedule.
    expect(CronValidator.validate('0 0 31 2 MON'), isNull);
  });
}
