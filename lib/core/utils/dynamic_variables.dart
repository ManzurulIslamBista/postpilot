import 'dart:math';

/// Postman's built-in `{{$name}}` variables. Every call to [resolve] draws a
/// fresh value, so two occurrences in one request differ — like Postman.
///
/// Values are test data, not secrets: names, addresses and passwords come from
/// small built-in lists and the injected [Random]. `$randomEmail` uses the
/// reserved example.* domains so a run can never mail a real inbox, and the
/// `$random*Date*` values are ISO-8601 (parseable by APIs) rather than
/// Postman's locale-formatted string.
final class DynamicVariables {
  /// [random] and [clock] exist so tests can pin the output.
  DynamicVariables({Random? random, DateTime Function()? clock})
      : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  /// What a resolver without its own generator uses.
  static final DynamicVariables shared = DynamicVariables();

  /// Every supported name, `$`-prefixed exactly as written inside `{{ }}`.
  static final List<String> names = List.unmodifiable(_generators.keys.toList()..sort());

  final Random _random;
  final DateTime Function() _clock;

  /// The value for [name] (with its `$`), or null when it isn't a built-in.
  String? resolve(String name) => _generators[name]?.call(this);

  static final Map<String, String Function(DynamicVariables)> _generators = {
    r'$guid': (v) => v._uuid(),
    r'$randomUUID': (v) => v._uuid(),
    r'$timestamp': (v) => '${v._clock().millisecondsSinceEpoch ~/ 1000}',
    r'$isoTimestamp': (v) => _iso(v._clock()),
    r'$randomInt': (v) => '${v._random.nextInt(1001)}',
    r'$randomBoolean': (v) => '${v._random.nextBool()}',
    r'$randomAlphaNumeric': (v) => v._chars(_alphanumeric, 1),
    r'$randomHexColor': (v) => '#${v._hex(6)}',
    r'$randomColor': (v) => v._pick(_colors),
    r'$randomIP': (v) => v._ipv4(),
    r'$randomIPV6': (v) => List.generate(8, (_) => v._hex(4)).join(':'),
    r'$randomMACAddress': (v) => List.generate(6, (_) => v._hex(2)).join(':'),
    r'$randomPassword': (v) => v._chars('$_alphanumeric${_alphanumeric.toUpperCase()}', 15),
    r'$randomWord': (v) => v._pick(_words),
    r'$randomLoremWord': (v) => v._pick(_lorem),
    r'$randomLoremWords': (v) => v._loremWords(3),
    r'$randomLoremSentence': (v) => v._sentence(),
    r'$randomLoremParagraph': (v) => List.generate(3, (_) => v._sentence()).join(' '),
    r'$randomFirstName': (v) => v._pick(_firstNames),
    r'$randomLastName': (v) => v._pick(_lastNames),
    r'$randomFullName': (v) => '${v._pick(_firstNames)} ${v._pick(_lastNames)}',
    r'$randomUserName': (v) => v._userName(),
    r'$randomEmail': (v) => '${v._userName().toLowerCase()}@${v._pick(_emailDomains)}',
    r'$randomPhoneNumber': (v) => '${2 + v._random.nextInt(8)}${v._digits(2)}-${v._digits(3)}-${v._digits(4)}',
    r'$randomCity': (v) => v._pick(_cities),
    r'$randomCountry': (v) => v._pick(_countries).$1,
    r'$randomCountryCode': (v) => v._pick(_countries).$2,
    r'$randomStreetName': (v) => v._streetName(),
    r'$randomStreetAddress': (v) => '${1 + v._random.nextInt(9999)} ${v._streetName()}',
    r'$randomCompanyName': (v) => '${v._pick(_lastNames)} ${v._pick(_companySuffixes)}',
    r'$randomJobTitle': (v) => v._pick(_jobTitles),
    r'$randomDomainWord': (v) => v._pick(_words),
    r'$randomDomainSuffix': (v) => v._pick(_domainSuffixes),
    r'$randomDomainName': (v) => v._domainName(),
    r'$randomUrl': (v) => 'https://${v._domainName()}',
    r'$randomDateFuture': (v) => v._dateWithin(1, _year),
    r'$randomDatePast': (v) => v._dateWithin(-_year, -1),
    r'$randomDateRecent': (v) => v._dateWithin(-_day, 0),
  };

  static const _day = 24 * 60 * 60;
  static const _year = 365 * _day;

  /// Millisecond precision on every platform: Dart's own ISO string carries
  /// microseconds on the VM but not on web.
  static String _iso(DateTime time) =>
      DateTime.fromMillisecondsSinceEpoch(time.millisecondsSinceEpoch, isUtc: true).toIso8601String();

  T _pick<T>(List<T> items) => items[_random.nextInt(items.length)];

  String _chars(String alphabet, int length) =>
      List.generate(length, (_) => alphabet[_random.nextInt(alphabet.length)]).join();

  String _digits(int length) => _chars('0123456789', length);

  String _hex(int length) => _chars('0123456789abcdef', length);

  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _ipv4() =>
      [1 + _random.nextInt(254), _random.nextInt(256), _random.nextInt(256), 1 + _random.nextInt(254)].join('.');

  String _loremWords(int count) => List.generate(count, (_) => _pick(_lorem)).join(' ');

  String _sentence() {
    final words = _loremWords(6 + _random.nextInt(7));
    return '${words[0].toUpperCase()}${words.substring(1)}.';
  }

  /// The numeric suffix keeps repeated draws from colliding, which matters when
  /// a run registers a new user every iteration.
  String _userName() => '${_pick(_firstNames)}${_pick(const ['.', '_'])}${_pick(_lastNames)}${_random.nextInt(1000)}';

  String _streetName() => '${_pick(_streets)} ${_pick(_streetSuffixes)}';

  String _domainName() => '${_pick(_words)}-${_pick(_words)}.${_pick(_domainSuffixes)}';

  /// A moment [fromSeconds]..[toSeconds] (inclusive) away from the clock's now.
  String _dateWithin(int fromSeconds, int toSeconds) =>
      _iso(_clock().add(Duration(seconds: fromSeconds + _random.nextInt(toSeconds - fromSeconds + 1))));

  static const _alphanumeric = 'abcdefghijklmnopqrstuvwxyz0123456789';

  static const _colors = [
    'red', 'green', 'blue', 'yellow', 'orange', 'purple', 'pink', 'brown', 'black', 'white', 'gray', 'cyan',
    'magenta', 'teal', 'azure', 'lime', 'maroon', 'navy', 'olive', 'silver', 'violet', 'indigo', 'turquoise',
    'ivory', 'salmon', 'plum', 'lavender', 'mint', 'tan', 'gold',
  ];

  static const _words = [
    'account', 'anchor', 'balance', 'basket', 'bridge', 'camera', 'candle', 'circle', 'coffee', 'copper', 'desert',
    'dragon', 'ember', 'engine', 'feather', 'forest', 'garden', 'glacier', 'hammer', 'harbor', 'island', 'ivory',
    'jacket', 'jungle', 'kettle', 'kitten', 'ladder', 'lantern', 'market', 'meadow', 'mirror', 'needle', 'notebook',
    'orange', 'orchard', 'pebble', 'pencil', 'planet', 'quartz', 'river', 'rocket', 'saddle', 'signal', 'ticket',
    'tunnel', 'umbrella', 'valley', 'window', 'yellow', 'zenith',
  ];

  static const _lorem = [
    'lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur', 'adipiscing', 'elit', 'sed', 'do', 'eiusmod', 'tempor',
    'incididunt', 'ut', 'labore', 'et', 'dolore', 'magna', 'aliqua', 'enim', 'ad', 'minim', 'veniam', 'quis',
    'nostrud', 'exercitation', 'ullamco', 'laboris', 'nisi', 'aliquip', 'ex', 'ea', 'commodo', 'consequat', 'duis',
    'aute', 'irure', 'in', 'reprehenderit', 'voluptate', 'velit', 'esse', 'cillum', 'fugiat', 'nulla', 'pariatur',
    'excepteur', 'sint', 'occaecat', 'cupidatat', 'non', 'proident', 'sunt', 'culpa', 'qui', 'officia', 'deserunt',
    'mollit', 'anim', 'id', 'est', 'laborum',
  ];

  static const _firstNames = [
    'Ada', 'Aisha', 'Amara', 'Arjun', 'Ava', 'Carlos', 'Chen', 'Daniel', 'Elena', 'Emma', 'Ethan', 'Fatima', 'Hana',
    'Ibrahim', 'Isabella', 'Ivan', 'James', 'Kenji', 'Layla', 'Liam', 'Lucas', 'Maria', 'Mei', 'Mia', 'Noah',
    'Olivia', 'Omar', 'Priya', 'Rahim', 'Sofia', 'Yuki', 'Zara',
  ];

  static const _lastNames = [
    'Ahmed', 'Anderson', 'Bennett', 'Brown', 'Chowdhury', 'Clark', 'Davis', 'Fernandez', 'Garcia', 'Hassan', 'Ito',
    'Jensen', 'Johnson', 'Khan', 'Kim', 'Lee', 'Martin', 'Miller', 'Mohamed', 'Nguyen', 'Okafor', 'Patel', 'Rahman',
    'Rossi', 'Santos', 'Schmidt', 'Silva', 'Smith', 'Tanaka', 'Taylor', 'Walker', 'Wilson',
  ];

  static const _cities = [
    'Amsterdam', 'Austin', 'Berlin', 'Cairo', 'Chicago', 'Denver', 'Dhaka', 'Dubai', 'Dublin', 'Helsinki', 'Jakarta',
    'Lagos', 'Lima', 'Lisbon', 'London', 'Madrid', 'Melbourne', 'Mumbai', 'Nairobi', 'Oslo', 'Paris', 'Prague',
    'Rome', 'Seattle', 'Seoul', 'Singapore', 'Sydney', 'Tokyo', 'Toronto', 'Vienna', 'Warsaw', 'Zurich',
  ];

  static const _countries = [
    ('Australia', 'AU'), ('Bangladesh', 'BD'), ('Brazil', 'BR'), ('Canada', 'CA'), ('China', 'CN'), ('Egypt', 'EG'),
    ('France', 'FR'), ('Germany', 'DE'), ('India', 'IN'), ('Indonesia', 'ID'), ('Ireland', 'IE'), ('Italy', 'IT'),
    ('Japan', 'JP'), ('Kenya', 'KE'), ('Mexico', 'MX'), ('Netherlands', 'NL'), ('Nigeria', 'NG'), ('Norway', 'NO'),
    ('Pakistan', 'PK'), ('Poland', 'PL'), ('Portugal', 'PT'), ('Singapore', 'SG'), ('South Korea', 'KR'),
    ('Spain', 'ES'), ('Sweden', 'SE'), ('Switzerland', 'CH'), ('Turkey', 'TR'), ('United Kingdom', 'GB'),
    ('United States', 'US'), ('Vietnam', 'VN'),
  ];

  static const _streets = [
    'Cedar', 'Church', 'Elm', 'Highland', 'Hill', 'Lake', 'Maple', 'Meadow', 'Mill', 'Oak', 'Park', 'Pine', 'River',
    'Spring', 'Sunset', 'Willow',
  ];

  static const _streetSuffixes = ['Street', 'Avenue', 'Road', 'Lane', 'Drive', 'Court', 'Boulevard', 'Way'];

  static const _companySuffixes = [
    'Group', 'Holdings', 'Industries', 'Labs', 'Partners', 'Solutions', 'Systems', 'Works',
  ];

  static const _jobTitles = [
    'Software Engineer', 'Product Manager', 'Data Analyst', 'Designer', 'QA Engineer', 'DevOps Engineer',
    'Accountant', 'Sales Manager', 'Support Specialist', 'Marketing Lead', 'Project Manager', 'Technical Writer',
    'Security Analyst', 'Operations Manager', 'Customer Success Manager', 'HR Coordinator',
  ];

  static const _domainSuffixes = ['com', 'net', 'org', 'io', 'dev', 'info'];

  static const _emailDomains = ['example.com', 'example.net', 'example.org'];
}
