import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/flavor_export/domain/services/flavor_exporter.dart';

FlavorVariable _v(String key, String value, {bool secret = false}) => FlavorVariable(key, value, isSecret: secret);

FlavorEnvironment _env(String name, String flavor, List<FlavorVariable> variables) =>
    FlavorEnvironment(name: name, flavor: flavor, variables: variables);

final _dev = _env('Development', 'dev', [
  _v('baseUrl', 'http://localhost:3000'),
  _v('apiUrl', '{{baseUrl}}/api'),
  _v('timeoutMs', '5000'),
  _v('debug', 'true'),
  _v('api_key', 'dev-key-1'),
]);

final _prod = _env('Production', 'prod', [
  _v('baseUrl', 'https://api.example.com'),
  _v('apiUrl', '{{baseUrl}}/api'),
  _v('timeoutMs', '15000'),
  _v('debug', 'false'),
  _v('api_key', 'prod-secret'),
]);

const _noSecrets = {'baseUrl', 'apiUrl', 'timeoutMs', 'debug'};

String _text(FlavorExport e, String path) => e.fileAt(path)!.content;

void main() {
  group('names and types', () {
    test('define names: upper snake case, characters a define cannot hold, never a leading digit', () {
      String d(String k, {bool snake = true}) => FlavorExporter.defineName(k, upperSnake: snake);
      expect(d('baseUrl'), 'BASE_URL');
      expect(d('API_URL'), 'API_URL');
      expect(d('apiKey2'), 'API_KEY2');
      expect(d('base-url'), 'BASE_URL');
      expect(d('APIKey'), 'API_KEY');
      expect(d('2fa'), '_2FA');
      expect(d('base url', snake: false), 'base_url');
      expect(d('baseUrl', snake: false), 'baseUrl');
    });

    test('Dart getters: camel case from the define, keywords and digits made legal', () {
      expect(FlavorExporter.getterName('BASE_URL'), 'baseUrl');
      expect(FlavorExporter.getterName('baseUrl'), 'baseUrl');
      expect(FlavorExporter.getterName('API_key'), 'apiKey');
      expect(FlavorExporter.getterName('_2FA'), 'v2fa');
      expect(FlavorExporter.getterName('NEW'), 'newValue');
      expect(FlavorExporter.getterName('FLAVOR'), 'flavorValue', reason: 'AppConfig.flavor is the build flavor');
    });

    test('type guessing: bool (exact spelling), int (no leading zero), URL, else text', () {
      FlavorValueType t(String v) => FlavorExporter.guessType(v);
      expect(t('true'), FlavorValueType.boolean);
      expect(t('false'), FlavorValueType.boolean);
      expect(t('True'), FlavorValueType.string, reason: 'bool.fromEnvironment only reads true and false');
      expect(t('5000'), FlavorValueType.integer);
      expect(t('-3'), FlavorValueType.integer);
      expect(t('0'), FlavorValueType.integer);
      expect(t('007'), FlavorValueType.string, reason: 'a zero padded id is text');
      expect(t('12345678901234567890'), FlavorValueType.string, reason: 'more digits than an int holds');
      expect(t('http://10.0.2.2:3000/api'), FlavorValueType.url);
      expect(t('wss://chat.example.com/socket'), FlavorValueType.url);
      expect(t('ftp://files.example.com'), FlavorValueType.string);
      expect(t('localhost:3000'), FlavorValueType.string);
      expect(t(''), FlavorValueType.string);
      expect(t('hello world'), FlavorValueType.string);
    });

    test('environment names map to the usual flavor names', () {
      String f(String n) => FlavorExporter.defaultFlavorName(n);
      expect(f('Development'), 'dev');
      expect(f('Local'), 'dev');
      expect(f('Odoo 17 Local'), 'dev');
      expect(f('Staging'), 'staging');
      expect(f('UAT'), 'staging');
      expect(f('Pre-Production'), 'staging');
      expect(f('Production'), 'prod');
      expect(f('Live'), 'prod');
      expect(f('Sandbox Alpha'), 'sandbox_alpha');
      expect(f('!!!'), 'env');
    });

    test('secrets: a flag, a credential name, a credential value or a password in a URL; plain config is not', () {
      expect(FlavorExporter.isSecretVariable(_v('api_key', 'x')), isTrue);
      expect(FlavorExporter.isSecretVariable(_v('dbPass', 'x')), isTrue);
      expect(FlavorExporter.isSecretVariable(_v('anything', 'x', secret: true)), isTrue);
      expect(FlavorExporter.isSecretVariable(_v('webhook', 'ghp_abcdefghijklmnopqrstuvwxyz0123456789')), isTrue);
      expect(FlavorExporter.isSecretVariable(_v('dbUrl', 'postgres://admin:hunter2@db.local/app')), isTrue);
      expect(FlavorExporter.isSecretVariable(_v('baseUrl', 'https://api.example.com')), isFalse);
      expect(FlavorExporter.isSecretVariable(_v('token_url', 'https://auth.example.com/token')), isFalse);
      expect(FlavorExporter.defaultSelection([_dev]), _noSecrets);
    });

    test('merging scopes: the environment hides a global of the same name, disabled ones are the caller\'s to drop', () {
      final merged = FlavorExporter.mergeScopes([_v('a', '1'), _v('b', '2')], [_v('b', '3'), _v('c', '4'), _v(' ', 'blank')]);
      expect({for (final v in merged) v.key: v.value}, {'a': '1', 'b': '3', 'c': '4'});
    });
  });

  group('quoting', () {
    test('.env values: bare when plain, single quotes keep \$ and # literal, double quotes only when a quote or line break forces it', () {
      String v(String s) => FlavorExporter.dotenvValue(s);
      expect(v(''), '');
      expect(v('plain'), 'plain');
      expect(v('http://localhost:3000/api'), 'http://localhost:3000/api');
      expect(v('aGVsbG8=='), 'aGVsbG8==');
      expect(v('https://a.b/c?x=1'), "'https://a.b/c?x=1'");
      expect(v('a b'), "'a b'");
      expect(v(r'cost $5 #1'), r"'cost $5 #1'");
      expect(v('say "hi"'), "'say \"hi\"'");
      expect(v(r'C:\dir'), r"'C:\dir'");
      expect(v("it's"), '"it\'s"');
      expect(v('it\'s "x"'), r'''"it's \"x\""''');
      expect(v(r"it's $HOME"), r'''"it's \$HOME"''');
      expect(v('a\nb'), r'"a\nb"');
      expect(v('a\r\nb'), r'"a\nb"');
      expect(v('C:\\dir\n2'), r'"C:\\dir\n2"');
      expect(FlavorExporter.dotenvLine('K', 'a b'), "K='a b'");
    });

    test('env.json: quotes, line breaks and dollar signs survive a round trip, every value is a string', () {
      const values = {'A': 'x"y', 'B': 'line1\nline2', 'C': r'$5 and ${HOME}', 'D': '5000', 'E': "it's"};
      final text = FlavorExporter.jsonFile(values);
      expect(jsonDecode(text), values);
      expect(text, contains(r'"A": "x\"y"'));
      expect(text, contains(r'"B": "line1\nline2"'));
      expect(text, contains(r'"C": "$5 and ${HOME}"'));
      expect(text, contains('"D": "5000"'));
      expect(text.endsWith('\n'), isTrue);
    });

    test('--dart-define arguments are quoted only when needed, per shell', () {
      const values = {'PLAIN': 'x', 'SPACE': 'a b', 'QUOTE': "it's", 'DOLLAR': r'$5', 'URL': 'http://h:1/p'};
      expect(FlavorExporter.dartDefineArguments(values, powershell: false), [
        '--dart-define=PLAIN=x',
        "'--dart-define=SPACE=a b'",
        r"""'--dart-define=QUOTE=it'\''s'""",
        r"'--dart-define=DOLLAR=$5'",
        '--dart-define=URL=http://h:1/p',
      ]);
      expect(FlavorExporter.dartDefineArguments(values, powershell: true), [
        '--dart-define=PLAIN=x',
        "'--dart-define=SPACE=a b'",
        "'--dart-define=QUOTE=it''s'",
        r"'--dart-define=DOLLAR=$5'",
        '--dart-define=URL=http://h:1/p',
      ]);
    });
  });

  group('export', () {
    FlavorExport run(List<FlavorEnvironment> envs, {Set<String> keys = _noSecrets, bool defaults = true, bool flavorArg = false, bool snake = true}) =>
        FlavorExporter.export(
          envs,
          FlavorExportOptions(includedKeys: keys, embedDefaults: defaults, passFlavorArgument: flavorArg, upperSnakeNames: snake, appName: 'my_app'),
        );

    test('several environments: one .env and one env.json per flavor, references resolved with the app\'s resolver', () {
      final e = run([_dev, _prod]);
      expect(e.files.map((f) => f.path), [
        '.env.dev', 'env.dev.json', '.env.prod', 'env.prod.json', 'lib/config/app_config.dart', '.vscode/launch.json', 'flutter_run_commands.txt',
      ]);
      expect(e.values['dev'], {
        'FLAVOR': 'dev',
        'BASE_URL': 'http://localhost:3000',
        'API_URL': 'http://localhost:3000/api',
        'TIMEOUT_MS': '5000',
        'DEBUG': 'true',
      });
      expect(e.values['prod']!['API_URL'], 'https://api.example.com/api');
      expect(e.warnings, isEmpty);
      expect(e.hasSecretPlaceholders, isFalse);

      final env = _text(e, '.env.dev');
      expect(env, contains('FLAVOR=dev\n'));
      expect(env, contains('BASE_URL=http://localhost:3000\n'));
      expect(env, contains('API_URL=http://localhost:3000/api\n'));
      expect(env, contains('DEBUG=true\n'));
      expect(env, isNot(contains('{{')));
      expect(jsonDecode(_text(e, 'env.prod.json')), e.values['prod']);
    });

    test('one environment: plain file names', () {
      final e = run([_dev]);
      expect(e.files.map((f) => f.path).take(2), ['.env', 'env.json']);
      expect(_text(e, 'flutter_run_commands.txt'), contains('flutter run --dart-define-from-file=env.json'));
    });

    test('secrets are unticked by default; ticked, they are empty placeholders everywhere, with the warning, and the value is in no file', () {
      final withKey = run([_dev, _prod], keys: {..._noSecrets, 'api_key'});
      expect(withKey.hasSecretPlaceholders, isTrue);
      expect(withKey.values['dev']!['API_KEY'], '');
      expect(withKey.values['prod']!['API_KEY'], '');
      expect(_text(withKey, '.env.dev'), contains('# API_KEY: secret placeholder, empty on purpose.\nAPI_KEY=\n'));
      expect(jsonDecode(_text(withKey, 'env.dev.json'))['API_KEY'], '');
      expect(_text(withKey, 'flutter_run_commands.txt'), contains('compiled into the app'));
      for (final f in withKey.files) {
        expect(f.content, isNot(contains('dev-key-1')), reason: f.path);
        expect(f.content, isNot(contains('prod-secret')), reason: f.path);
      }
      final without = run([_dev, _prod]);
      expect(without.values['dev']!.containsKey('API_KEY'), isFalse);
      expect(_text(without, '.env.dev'), isNot(contains('API_KEY')));
    });

    test('a secret in one environment only is a secret in all of them', () {
      final a = _env('Development', 'dev', [_v('endpoint', 'https://dev.example.com', secret: true)]);
      final b = _env('Production', 'prod', [_v('endpoint', 'https://prod.example.com')]);
      final e = run([a, b], keys: {'endpoint'});
      expect(e.values['prod']!['ENDPOINT'], '');
      expect(e.keys.single.isSecret, isTrue);
    });

    test('a reference to an undefined variable stays and is reported; a reference to a secret is never copied', () {
      final env = _env('Development', 'dev', [
        _v('api', '{{missing}}/v1'),
        _v('header', 'Bearer {{api_key}}'),
        _v('trace', r'{{$guid}}'),
        _v('api_key', 'real-secret-value'),
      ]);
      final e = run([env], keys: {'api', 'header', 'trace'});
      expect(e.values['dev']!['API'], '{{missing}}/v1');
      expect(e.values['dev']!['HEADER'], 'Bearer {{api_key}}');
      expect(e.values['dev']!['TRACE'], r'{{$guid}}');
      expect(e.warnings.where((w) => w.contains('{{missing}}')), hasLength(1));
      expect(e.warnings.where((w) => w.contains('secret {{api_key}}')), hasLength(1));
      expect(e.warnings.where((w) => w.contains('generated value')), hasLength(1));
      for (final f in e.files) {
        expect(f.content, isNot(contains('real-secret-value')), reason: f.path);
      }
    });

    test('a variable missing from one environment is empty there and says so; names that collide are renamed', () {
      final a = _env('Development', 'dev', [_v('base-url', 'http://a'), _v('baseUrl', 'http://b'), _v('only_dev', '1')]);
      final b = _env('Production', 'prod', [_v('base-url', 'https://a')]);
      final e = run([a, b], keys: {'base-url', 'baseUrl', 'only_dev'});
      expect(e.keys.map((k) => k.name), ['BASE_URL', 'BASE_URL_2', 'ONLY_DEV']);
      expect(e.keys.map((k) => k.getter), ['baseUrl', 'baseUrl2', 'onlyDev']);
      expect(e.values['prod']!['ONLY_DEV'], '');
      expect(e.warnings.any((w) => w.contains('"baseUrl" would be exported as BASE_URL')), isTrue);
      expect(e.warnings.any((w) => w.contains('"only_dev" is not defined in "Production"')), isTrue);
    });

    test('two environments with the same flavor name are told apart', () {
      final e = run([_env('A', 'dev', const []), _env('B', 'dev', const [])], keys: const {});
      expect(e.values.keys, ['dev', 'dev_2']);
      expect(e.warnings.any((w) => w.contains('"B" became "dev_2"')), isTrue);
    });

    test('AppConfig: typed getters, defaults from the first flavor, flavor flags, no default for a secret', () {
      final e = run([_dev, _prod], keys: {..._noSecrets, 'api_key'});
      final dart = _text(e, 'lib/config/app_config.dart');
      expect(dart, contains("static const String flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');"));
      expect(dart, contains("static bool get isDev => flavor == 'dev';"));
      expect(dart, contains("static bool get isProd => flavor == 'prod';"));
      expect(dart, contains("static const String baseUrl = String.fromEnvironment('BASE_URL', defaultValue: 'http://localhost:3000');"));
      expect(dart, contains('static Uri get baseUri => Uri.parse(baseUrl);'));
      expect(dart, contains("static const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');"));
      expect(dart, contains('static Uri get apiUri => Uri.parse(apiUrl);'));
      expect(dart, contains("static const int timeoutMs = int.fromEnvironment('TIMEOUT_MS', defaultValue: 5000);"));
      expect(dart, contains("static const bool debug = bool.fromEnvironment('DEBUG', defaultValue: true);"));
      expect(dart, contains("static const String apiKey = String.fromEnvironment('API_KEY');"));
      expect(dart, contains('flutter run --dart-define-from-file=env.dev.json'));
      expect(dart, contains('flutter run --dart-define-from-file=env.prod.json'));
      expect(dart, contains('abstract final class AppConfig {'));
      expect(dart, isNot(contains('dev-key-1')));
    });

    test('AppConfig without defaults, with a type that differs between flavors, with quotes and dollar signs in a default', () {
      final a = _env('Development', 'dev', [_v('port', '3000'), _v('note', r"it's $5")]);
      final b = _env('Production', 'prod', [_v('port', 'abc'), _v('note', 'x')]);
      final plain = _text(run([a, b], keys: {'port', 'note'}, defaults: false), 'lib/config/app_config.dart');
      expect(plain, contains("static const String port = String.fromEnvironment('PORT');"));
      expect(plain, contains("static const String note = String.fromEnvironment('NOTE');"));
      expect(plain, isNot(contains('defaultValue: 3000')));
      final withDefaults = _text(run([a, b], keys: {'port', 'note'}), 'lib/config/app_config.dart');
      expect(withDefaults, contains(r"defaultValue: 'it\'s \$5'"));
      expect(withDefaults, contains("static const String port = String.fromEnvironment('PORT', defaultValue: '3000');"));
    });

    test('names as written when upper snake case is off', () {
      final e = run([_dev], snake: false);
      expect(e.values['dev']!.keys, ['FLAVOR', 'baseUrl', 'apiUrl', 'timeoutMs', 'debug']);
      expect(_text(e, '.env'), contains('baseUrl=http://localhost:3000\n'));
    });

    test('launch configurations: one per flavor, --flavor only when asked', () {
      final plain = jsonDecode(_text(run([_dev, _prod]), '.vscode/launch.json')) as Map<String, dynamic>;
      expect(plain['version'], '0.2.0');
      final configs = plain['configurations'] as List<dynamic>;
      expect(configs.map((c) => (c as Map)['name']), ['my_app (dev)', 'my_app (prod)']);
      expect((configs.first as Map)['args'], ['--dart-define-from-file=env.dev.json']);
      expect((configs.first as Map)['type'], 'dart');
      expect((configs.first as Map)['request'], 'launch');
      final flavored = jsonDecode(_text(run([_dev, _prod], flavorArg: true), '.vscode/launch.json')) as Map<String, dynamic>;
      expect(((flavored['configurations'] as List).last as Map)['args'], ['--dart-define-from-file=env.prod.json', '--flavor', 'prod']);
    });

    test('run commands: the file form, both shells, the Android Studio line', () {
      final e = run([_dev, _prod], flavorArg: true);
      final text = _text(e, 'flutter_run_commands.txt');
      expect(text, contains('  flutter run --dart-define-from-file=env.dev.json --flavor dev\n'));
      expect(text, contains('  flutter build apk --dart-define-from-file=env.prod.json --flavor prod\n'));
      expect(
        text,
        contains('  flutter run --flavor dev --dart-define=FLAVOR=dev --dart-define=BASE_URL=http://localhost:3000 '
            '--dart-define=API_URL=http://localhost:3000/api --dart-define=TIMEOUT_MS=5000 --dart-define=DEBUG=true\n'),
      );
      expect(text, contains('Additional run args:\n  --dart-define-from-file=env.dev.json --flavor dev\n'));
      expect(text, contains('.vscode/launch.json'));
      expect(text, isNot(contains('WARNING')), reason: 'no secrets in this export');
    });

    test('nothing ticked still gives files with the flavor, and says so', () {
      final e = run([_dev], keys: const {});
      expect(e.values['dev'], {'FLAVOR': 'dev'});
      expect(e.warnings.single, contains('No variable is ticked'));
    });
  });
}
