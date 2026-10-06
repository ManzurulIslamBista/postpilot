// Pure Dart.

/// Checks a cron expression the way GitHub Actions reads it: five fields (minute, hour, day of month, month, day of
/// week) with `*`, lists (`1,15`), ranges (`1-5`) and steps (`*/15`, `10-50/10`); month and weekday names
/// (`JAN`, `MON`) work, the shortcuts of some cron programs (`@daily`) and `?`, `L` or `#` do not. GitHub starts a
/// scheduled workflow at most every five minutes, so an expression that would fire more often is refused.
abstract final class CronValidator {
  /// The shortest gap GitHub allows between two scheduled runs.
  static const minimumGapMinutes = 5;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  static const _days = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

  static const _fields = [
    _Field('minute', 0, 59),
    _Field('hour', 0, 23),
    _Field('day of month', 1, 31),
    _Field('month', 1, 12, names: _months, nameBase: 1),
    _Field('day of week', 0, 6, names: _days, nameBase: 0),
  ];

  /// What is wrong with [cron], in words that say what to change; null when it is a valid schedule.
  static String? validate(String cron) {
    final text = cron.trim();
    if (text.isEmpty) return 'Enter a cron expression, for example 17 6 * * * (every day at 06:17 UTC).';
    if (text.startsWith('@')) return 'GitHub Actions does not understand "$text". Write the five fields, for example 17 6 * * *.';
    final parts = text.split(RegExp(r'\s+'));
    if (parts.length != 5) {
      return 'A cron expression has five fields (minute hour day-of-month month day-of-week), not ${parts.length}: "$text".';
    }
    final sets = <Set<int>>[];
    for (final (i, part) in parts.indexed) {
      final result = _parseField(_fields[i], part);
      if (result.error != null) return result.error;
      sets.add(result.values);
    }
    final gap = _smallestGap(sets[0], sets[1]);
    if (gap != null && gap < minimumGapMinutes) {
      return 'This would start a run every $gap minute${gap == 1 ? '' : 's'}. GitHub starts scheduled workflows at most every '
          '$minimumGapMinutes minutes: use something like */15 in the minute field.';
    }
    if (sets[2].isNotEmpty && sets[3].isNotEmpty && !_dayExists(sets[2], sets[3], parts[2] != '*' && parts[4] == '*')) {
      return 'The day of month and month never occur together (for example 31 in a month that has 30 days).';
    }
    return null;
  }

  static bool isValid(String cron) => validate(cron) == null;

  /// The smallest gap, in minutes, between two runs of a day, or null when it runs once or never.
  static int? _smallestGap(Set<int> minutes, Set<int> hours) {
    final times = <int>[
      for (final h in hours.toList()..sort())
        for (final m in minutes.toList()..sort()) h * 60 + m,
    ];
    if (times.length < 2) return null;
    var smallest = times.first + 1440 - times.last;
    for (var i = 1; i < times.length; i++) {
      final gap = times[i] - times[i - 1];
      if (gap < smallest) smallest = gap;
    }
    return smallest;
  }

  /// Whether at least one of the days of month exists in at least one of the months. When only the day of month is
  /// restricted (the weekday is `*`), a day that no chosen month has can never run.
  static bool _dayExists(Set<int> daysOfMonth, Set<int> months, bool onlyDayOfMonth) {
    if (!onlyDayOfMonth) return true;
    const longest = {1: 31, 2: 29, 3: 31, 4: 30, 5: 31, 6: 30, 7: 31, 8: 31, 9: 30, 10: 31, 11: 30, 12: 31};
    return daysOfMonth.any((d) => months.any((m) => d <= longest[m]!));
  }

  static ({Set<int> values, String? error}) _parseField(_Field field, String text) {
    final values = <int>{};
    for (final item in text.split(',')) {
      if (item.isEmpty) return (values: values, error: 'The ${field.name} field "$text" has an empty entry.');
      final slash = item.indexOf('/');
      final base = slash < 0 ? item : item.substring(0, slash);
      int step = 1;
      if (slash >= 0) {
        final stepText = item.substring(slash + 1);
        final parsed = int.tryParse(stepText);
        if (parsed == null || parsed < 1) {
          return (values: values, error: 'The step "/$stepText" in the ${field.name} field must be a whole number from 1.');
        }
        step = parsed;
      }
      int from;
      int to;
      if (base == '*') {
        from = field.min;
        to = field.max;
      } else {
        final dash = base.indexOf('-');
        if (dash < 0) {
          final value = field.read(base);
          if (value == null) return (values: values, error: field.rangeError(base));
          from = value;
          // `5/10` means from 5 to the end in steps of 10.
          to = slash < 0 ? value : field.max;
        } else {
          final low = field.read(base.substring(0, dash));
          final high = field.read(base.substring(dash + 1));
          if (low == null) return (values: values, error: field.rangeError(base.substring(0, dash)));
          if (high == null) return (values: values, error: field.rangeError(base.substring(dash + 1)));
          if (low > high) {
            return (
              values: values,
              error: 'The range "$base" in the ${field.name} field goes backwards and a range cannot wrap around: '
                  'use two ranges, for example 22-23,0-5.',
            );
          }
          from = low;
          to = high;
        }
      }
      for (var v = from; v <= to; v += step) {
        values.add(v);
      }
    }
    return (values: values, error: null);
  }
}

final class _Field {
  final String name;
  final int min;
  final int max;
  final List<String>? names;
  final int nameBase;

  const _Field(this.name, this.min, this.max, {this.names, this.nameBase = 0});

  /// A number in range, or a name (`MON`, `jan`); null when it is neither.
  int? read(String text) {
    final upper = text.toUpperCase();
    final named = names?.indexOf(upper);
    if (named != null && named >= 0) return named + nameBase;
    final value = int.tryParse(text);
    if (value == null || value < min || value > max) return null;
    return value;
  }

  String rangeError(String text) {
    final numbers = 'a number from $min to $max';
    final allowed = names == null ? numbers : '$numbers or a name (${names!.take(3).join(', ')}...)';
    final hint = name == 'day of week' && text == '7' ? ' Sunday is 0 (or SUN) on GitHub.' : '';
    return 'The $name field takes $allowed, not "$text".$hint';
  }
}
