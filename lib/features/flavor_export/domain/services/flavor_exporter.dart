import 'dart:convert';
import '../../../../core/utils/variable_resolver.dart';
import '../../../dart_codegen/domain/entities/generated_file.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../../../request_builder/domain/services/code_generators/string_literals.dart';

/// The type a variable's value suggests, for the typed getters of the generated `AppConfig`.
enum FlavorValueType { string, url, integer, boolean }

/// One variable of an environment, as the person wrote it (references not resolved yet).
final class FlavorVariable {
  final String key;
  final String value;

  /// The person marked it as a secret; a name or value that looks like a credential counts as well (see
  /// [FlavorExporter.isSecretVariable]).
  final bool isSecret;

  const FlavorVariable(this.key, this.value, {this.isSecret = false});
}

/// An environment mapped to a flavor. [variables] are the effective ones: the enabled variables of the environment on top of
/// the enabled globals (see [FlavorExporter.mergeScopes]).
final class FlavorEnvironment {
  /// What the environment is called in the app (`Development`).
  final String name;

  /// What the flavor is called in the files (`dev`); normalised to lower-case letters, digits and underscores.
  final String flavor;
  final List<FlavorVariable> variables;

  const FlavorEnvironment({required this.name, required this.flavor, required this.variables});
}

final class FlavorExportOptions {
  /// Variable names (as written in the environments) that go into the files. A secret that is in this set is exported
  /// as an empty placeholder, never with its value.
  final Set<String> includedKeys;

  /// `baseUrl` becomes `BASE_URL`, the usual spelling of a `--dart-define` name. Off keeps the names as written.
  final bool upperSnakeNames;

  /// The first flavor's values become the `defaultValue`s in `AppConfig`, so a plain `flutter run` still works.
  final bool embedDefaults;

  /// Also pass `--flavor <name>` (the Android/iOS flavor of the same name) in the launch configurations and commands.
  final bool passFlavorArgument;

  /// Names the launch configurations (`my_app (dev)`).
  final String appName;

  const FlavorExportOptions({
    required this.includedKeys,
    this.upperSnakeNames = true,
    this.embedDefaults = true,
    this.passFlavorArgument = false,
    this.appName = 'app',
  });
}

/// One exported variable: the name it has in the environments, in the files and in Dart, and the type of its value.
final class FlavorKey {
  final String source;
  final String name;
  final String getter;
  final FlavorValueType type;
  final bool isSecret;

  const FlavorKey({required this.source, required this.name, required this.getter, required this.type, required this.isSecret});
}

final class FlavorExport {
  final List<GeneratedFile> files;

  /// Things the person must read before using the files: references left as they are, secrets, renamed keys.
  final List<String> warnings;
  final List<FlavorKey> keys;

  /// Flavor name to (file name of the variable to value) exactly as written to the files.
  final Map<String, Map<String, String>> values;

  /// At least one exported variable looks like a credential and was left empty on purpose.
  final bool hasSecretPlaceholders;

  const FlavorExport({
    required this.files,
    required this.warnings,
    required this.keys,
    required this.values,
    required this.hasSecretPlaceholders,
  });

  GeneratedFile? fileAt(String path) => files.where((f) => f.path == path).firstOrNull;
}

/// Turns environments into the files a Flutter project reads its configuration from: `.env` (flutter_dotenv), `env.json`
/// (`--dart-define-from-file`), `--dart-define` command lines, launch configurations and a typed `AppConfig`. Pure Dart, no
/// files are touched.
abstract final class FlavorExporter {
  static const appConfigPath = 'lib/config/app_config.dart';
  static const launchJsonPath = '.vscode/launch.json';
  static const commandsPath = 'flutter_run_commands.txt';

  /// The name of the variable that tells the app which flavor it was built for.
  static const flavorDefine = 'FLAVOR';

  /// What a `--dart-define` value in the app binary can never be: a real secret. Shown wherever one is included.
  static const secretWarning = 'A --dart-define value is compiled into the app and can be read back from the built binary '
      '(and from a .env file you ship as an asset). Secret variables are exported as empty placeholders: never put a '
      'real API key, password or private token into these files. Fetch secrets at run time from your backend.';

  // --- what is a secret, what is called what ------------------------------------------------------

  /// A variable that must not be exported with its value: marked as a secret, named like a credential (`api_key`,
  /// `db_password`), holding a credential-looking value, or a URL with a password in it.
  static bool isSecretVariable(FlavorVariable v) {
    if (v.isSecret || SecretNames.looksSecretKey(v.key)) return true;
    if (SecretNames.looksLikeCredential(v.value)) return true;
    final uri = Uri.tryParse(v.value.trim());
    return uri != null && uri.hasScheme && uri.userInfo.contains(':');
  }

  /// The effective variables of an environment: the enabled [environment] variables over the enabled [globals], the same
  /// precedence the app uses (a variable of the environment hides a global of the same name).
  static List<FlavorVariable> mergeScopes(List<FlavorVariable> globals, List<FlavorVariable> environment) {
    final merged = <String, FlavorVariable>{};
    for (final v in globals) {
      if (v.key.trim().isNotEmpty) merged[v.key] = v;
    }
    for (final v in environment) {
      if (v.key.trim().isNotEmpty) merged[v.key] = v;
    }
    return merged.values.toList();
  }

  /// Which variables are ticked at first: everything except the secrets.
  static Set<String> defaultSelection(Iterable<FlavorEnvironment> environments) => {
        for (final e in environments)
          for (final v in e.variables)
            if (v.key.trim().isNotEmpty && !isSecretVariable(v)) v.key,
      };

  /// `Development` is `dev`, `Staging` and `UAT` are `staging`, `Production` is `prod`; anything else is its own name in
  /// lower case. The person can edit the result.
  static String defaultFlavorName(String environmentName) {
    final n = environmentName.toLowerCase();
    if (RegExp(r'stag|uat|pre-?prod|\bqa\b').hasMatch(n)) return 'staging';
    if (RegExp(r'prod|\blive\b|release').hasMatch(n)) return 'prod';
    if (RegExp(r'\bdev|develop|local').hasMatch(n)) return 'dev';
    return slug(environmentName);
  }

  /// Lower-case letters, digits and underscores; never empty.
  static String slug(String name) {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'env' : s;
  }

  /// The name of [key] in the files. With [upperSnake]: `baseUrl`, `base-url` and `BASE_URL` are all `BASE_URL`. Without it
  /// only characters a define name cannot hold become `_`. A name never starts with a digit.
  static String defineName(String key, {required bool upperSnake}) {
    var s = key.trim();
    if (upperSnake) {
      s = s
          .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
          .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '')
          .toUpperCase();
    } else {
      s = s.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    }
    if (s.isEmpty) s = 'VARIABLE';
    return RegExp(r'^[0-9]').hasMatch(s) ? '_$s' : s;
  }

  static const _dartWords = {
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case', 'catch', 'class', 'const', 'continue', 'covariant',
    'default', 'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external', 'factory', 'false',
    'final', 'finally', 'for', 'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library', 'mixin',
    'new', 'null', 'of', 'on', 'operator', 'part', 'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static', 'super',
    'switch', 'sync', 'this', 'throw', 'true', 'try', 'type', 'typedef', 'var', 'void', 'when', 'while', 'with', 'yield',
    'hashCode', 'runtimeType', 'toString', 'noSuchMethod', 'flavor',
  };

  /// The Dart getter for a define name: `BASE_URL` is `baseUrl`, `apiV2` stays `apiV2`. A Dart keyword gets `Value` added.
  static String getterName(String define) {
    final words = [for (final w in define.split('_')) if (w.isNotEmpty) w];
    final parts = <String>[
      for (final w in words) w == w.toUpperCase() ? w.toLowerCase() : w,
    ];
    var name = '';
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      name += i == 0 ? p[0].toLowerCase() + p.substring(1) : p[0].toUpperCase() + p.substring(1);
    }
    if (name.isEmpty) name = 'variable';
    if (RegExp(r'^[0-9]').hasMatch(name)) name = 'v$name';
    return _dartWords.contains(name) ? '${name}Value' : name;
  }

  /// What [value] looks like: `true`/`false` (the only spellings `bool.fromEnvironment` reads), a whole number without a leading
  /// zero (a zip code or an id stays text), an http(s)/ws(s) URL with a host, otherwise text.
  static FlavorValueType guessType(String value) {
    final v = value.trim();
    if (v == 'true' || v == 'false') return FlavorValueType.boolean;
    if (RegExp(r'^(0|-?[1-9][0-9]{0,17})$').hasMatch(v)) return FlavorValueType.integer;
    final uri = Uri.tryParse(v);
    if (uri != null && RegExp(r'^(https?|wss?)$').hasMatch(uri.scheme) && uri.host.isNotEmpty) return FlavorValueType.url;
    return FlavorValueType.string;
  }

  // --- quoting for each target ---------------------------------------------------------------------

  static final _dotenvPlain = RegExp(r'^[A-Za-z0-9_@%+:,./=-]+$');

  /// [value] as the right-hand side of a flutter_dotenv line. Plain text stays bare. Anything else goes between single
  /// quotes, which flutter_dotenv reads literally (no `$VAR` expansion, `#` is not a comment). A value with a `'` or a line
  /// break needs double quotes, where `\`, `"` and `$` are escaped and a line break is written as `\n`.
  static String dotenvValue(String value) {
    if (value.isEmpty || _dotenvPlain.hasMatch(value)) return value;
    if (!value.contains("'") && !value.contains('\n') && !value.contains('\r')) return "'$value'";
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll(r'$', r'\$')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\n');
    return '"$escaped"';
  }

  /// `KEY=value` for flutter_dotenv.
  static String dotenvLine(String key, String value) => '$key=${dotenvValue(value)}';

  /// The flat JSON object `--dart-define-from-file` reads. Every value is a string: Flutter turns them into defines the same
  /// way, and `int.fromEnvironment` / `bool.fromEnvironment` parse them.
  static String jsonFile(Map<String, String> values) => '${const JsonEncoder.withIndent('  ').convert(values)}\n';

  /// `--dart-define=KEY=VALUE` arguments, each quoted for the shell only when it must be.
  static List<String> dartDefineArguments(Map<String, String> values, {required bool powershell}) => [
        for (final e in values.entries)
          _shellArgument('--dart-define=${e.key}=${e.value}', powershell: powershell),
      ];

  static String _shellArgument(String argument, {required bool powershell}) => RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(argument)
      ? argument
      : (powershell ? powershellString(argument) : shellQuote(argument));

  // --- the export ------------------------------------------------------------------------------------

  static FlavorExport export(List<FlavorEnvironment> environments, FlavorExportOptions options) {
    final warnings = <String>[];

    // Flavor names are file names and identifiers: unique, lower case.
    final flavors = <String>[];
    for (final env in environments) {
      var flavor = slug(env.flavor);
      if (flavors.contains(flavor)) {
        var n = 2;
        while (flavors.contains('${flavor}_$n')) {
          n++;
        }
        warnings.add('Two environments are both called "$flavor"; "${env.name}" became "${flavor}_$n".');
        flavor = '${flavor}_$n';
      }
      flavors.add(flavor);
    }

    // Variables to export, in the order they first appear.
    final sources = <String>[];
    for (final env in environments) {
      for (final v in env.variables) {
        final k = v.key;
        if (k.trim().isNotEmpty && options.includedKeys.contains(k) && !sources.contains(k)) sources.add(k);
      }
    }
    FlavorVariable? find(FlavorEnvironment env, String key) => env.variables.where((v) => v.key == key).firstOrNull;
    // A variable that is a secret in one environment is one in all of them: the key is exported empty everywhere.
    final secretKeys = {
      for (final env in environments)
        for (final v in env.variables)
          if (isSecretVariable(v)) v.key,
    };
    bool secretKey(String key) => secretKeys.contains(key);

    // Names in the files and in Dart, made unique. FLAVOR is ours.
    final usedDefines = <String>{flavorDefine};
    final usedGetters = <String>{'flavor'};
    final names = <String, ({String name, String getter})>{};
    for (final source in sources) {
      var name = defineName(source, upperSnake: options.upperSnakeNames);
      if (usedDefines.contains(name)) {
        var n = 2;
        while (usedDefines.contains('${name}_$n')) {
          n++;
        }
        warnings.add('"$source" would be exported as $name, which is already taken; it is ${name}_$n instead.');
        name = '${name}_$n';
      }
      usedDefines.add(name);
      var getter = getterName(name);
      var g = 2;
      final base = getter;
      while (usedGetters.contains(getter)) {
        getter = '$base$g';
        g++;
      }
      usedGetters.add(getter);
      names[source] = (name: name, getter: getter);
    }

    // The value of every exported variable in every flavor, references resolved like the app does.
    final values = <String, Map<String, String>>{};
    for (var i = 0; i < environments.length; i++) {
      final env = environments[i];
      final flavor = flavors[i];
      final out = <String, String>{flavorDefine: flavor};
      final secrets = secretKeys;
      // Secret values never take part in resolving: a reference to one must not copy it into a variable that is exported.
      final resolver = VariableResolver({for (final v in env.variables) if (!secrets.contains(v.key)) v.key: _maskGenerated(v.value)});
      for (final source in sources) {
        final name = names[source]!.name;
        final v = find(env, source);
        if (v == null) {
          out[name] = '';
          warnings.add('$flavor: "$source" is not defined in "${env.name}", so $name is empty in its files.');
          continue;
        }
        if (secretKey(source)) {
          out[name] = '';
          continue;
        }
        final masked = _maskGenerated(v.value);
        final undefined = resolver.undefinedIn(masked);
        out[name] = _unmaskGenerated(resolver.resolve(masked));
        for (final ref in undefined) {
          warnings.add(secrets.contains(ref)
              ? '$flavor: $name refers to the secret {{$ref}}. A secret is never exported, so the reference stays as {{$ref}} in the value.'
              : '$flavor: $name refers to {{$ref}}, which "${env.name}" does not define, so it stays as {{$ref}} in the value.');
        }
        if (RegExp(r'\{\{\$[\w.$-]+\}\}').hasMatch(out[name]!)) {
          warnings.add('$flavor: $name uses a generated value such as {{\$guid}}. It is made new for every request, so it stays as written.');
        }
      }
      values[flavor] = out;
    }

    // Types: what every non-empty value of a variable agrees on.
    final keys = <FlavorKey>[];
    var hasSecretPlaceholders = false;
    for (final source in sources) {
      final isSecret = secretKey(source);
      hasSecretPlaceholders = hasSecretPlaceholders || isSecret;
      final n = names[source]!;
      final seen = {
        for (final f in flavors)
          if (!isSecret && values[f]![n.name]!.isNotEmpty) guessType(values[f]![n.name]!),
      };
      final type = seen.length == 1 ? seen.single : FlavorValueType.string;
      keys.add(FlavorKey(source: source, name: n.name, getter: n.getter, type: isSecret ? FlavorValueType.string : type, isSecret: isSecret));
    }
    if (sources.isEmpty) warnings.add('No variable is ticked, so the files only carry the flavor name.');

    final single = environments.length == 1;
    String envPath(String flavor) => single ? '.env' : '.env.$flavor';
    String jsonPath(String flavor) => single ? 'env.json' : 'env.$flavor.json';
    String runArgs(String flavor) =>
        '--dart-define-from-file=${jsonPath(flavor)}${options.passFlavorArgument ? ' --flavor $flavor' : ''}';

    final files = <GeneratedFile>[];
    for (var i = 0; i < environments.length; i++) {
      final flavor = flavors[i];
      files.add(GeneratedFile(envPath(flavor), _dotenv(environments[i], flavor, values[flavor]!, keys)));
      files.add(GeneratedFile(jsonPath(flavor), jsonFile(values[flavor]!)));
    }
    files
      ..add(GeneratedFile(appConfigPath, _appConfig(environments, flavors, keys, values, options, jsonPath)))
      ..add(GeneratedFile(launchJsonPath, _launchJson(flavors, options)))
      ..add(GeneratedFile(commandsPath, _commands(environments, flavors, values, options, envPath, jsonPath, runArgs, hasSecretPlaceholders)));

    return FlavorExport(files: files, warnings: warnings, keys: keys, values: values, hasSecretPlaceholders: hasSecretPlaceholders);
  }

  // `{{$guid}}` is made new on every use, which has no meaning in a file: it is hidden from the resolver and put back.
  static const _generatedMark = '';
  static String _maskGenerated(String s) => s.replaceAll(r'{{$', _generatedMark);
  static String _unmaskGenerated(String s) => s.replaceAll(_generatedMark, r'{{$');

  // --- the files ---------------------------------------------------------------------------------------

  static String _dotenv(FlavorEnvironment env, String flavor, Map<String, String> values, List<FlavorKey> keys) {
    final secretNames = {for (final k in keys) if (k.isSecret) k.name};
    final b = StringBuffer()
      ..writeln('# Generated by PostPilot from the environment "${env.name}" (flavor $flavor), in flutter_dotenv format.')
      ..writeln('# Load it with dotenv.load(fileName: ...) after listing it under flutter > assets in pubspec.yaml.');
    if (secretNames.isNotEmpty) {
      b
        ..writeln('# Anything in this file ships inside the app. The empty values below are secret placeholders left empty on')
        ..writeln('# purpose: do not put a real secret here.');
    }
    for (final e in values.entries) {
      if (secretNames.contains(e.key)) b.writeln('# ${e.key}: secret placeholder, empty on purpose.');
      b.writeln(dotenvLine(e.key, e.value));
    }
    return b.toString();
  }

  static String _launchJson(List<String> flavors, FlavorExportOptions options) {
    final configurations = [
      for (final flavor in flavors)
        {
          'name': '${options.appName} ($flavor)',
          'request': 'launch',
          'type': 'dart',
          'args': [
            '--dart-define-from-file=${flavors.length == 1 ? 'env.json' : 'env.$flavor.json'}',
            if (options.passFlavorArgument) ...['--flavor', flavor],
          ],
        },
    ];
    return '${const JsonEncoder.withIndent('  ').convert({'version': '0.2.0', 'configurations': configurations})}\n';
  }

  static String _commands(
    List<FlavorEnvironment> environments,
    List<String> flavors,
    Map<String, Map<String, String>> values,
    FlavorExportOptions options,
    String Function(String) envPath,
    String Function(String) jsonPath,
    String Function(String) runArgs,
    bool hasSecrets,
  ) {
    final b = StringBuffer()
      ..writeln('Generated by PostPilot. Run these from the root of your Flutter project.')
      ..writeln();
    if (hasSecrets) {
      b
        ..writeln('WARNING: $secretWarning')
        ..writeln();
    }
    for (var i = 0; i < environments.length; i++) {
      final flavor = flavors[i];
      final flavorArg = options.passFlavorArgument ? ' --flavor $flavor' : '';
      final bash = dartDefineArguments(values[flavor]!, powershell: false).join(' ');
      final powershell = dartDefineArguments(values[flavor]!, powershell: true).join(' ');
      b
        ..writeln('=== ${environments[i].name} (flavor $flavor) ===')
        ..writeln()
        ..writeln('From the file (recommended):')
        ..writeln('  flutter run ${runArgs(flavor)}')
        ..writeln('  flutter build apk ${runArgs(flavor)}')
        ..writeln('  flutter build ios ${runArgs(flavor)}')
        ..writeln()
        ..writeln('The same values as separate defines, bash / zsh / Git Bash:')
        ..writeln('  flutter run$flavorArg $bash')
        ..writeln()
        ..writeln('The same values, PowerShell:')
        ..writeln('  flutter run$flavorArg $powershell')
        ..writeln()
        ..writeln('Android Studio / IntelliJ: Run > Edit Configurations > Additional run args:')
        ..writeln('  ${runArgs(flavor)}')
        ..writeln()
        ..writeln('VS Code: the configuration "${options.appName} ($flavor)" is in .vscode/launch.json.')
        ..writeln('flutter_dotenv file: ${envPath(flavor)}')
        ..writeln();
    }
    b
      ..writeln('Keep out of version control what is private to you, for example in .gitignore:')
      ..writeln('  .env')
      ..writeln('  .env.*')
      ..writeln('  env.json')
      ..writeln('  env.*.json');
    return b.toString();
  }

  static String _appConfig(
    List<FlavorEnvironment> environments,
    List<String> flavors,
    List<FlavorKey> keys,
    Map<String, Map<String, String>> values,
    FlavorExportOptions options,
    String Function(String) jsonPath,
  ) {
    final first = flavors.first;
    final b = StringBuffer()
      ..writeln('// Generated by PostPilot from the environments ${[for (final e in environments) '"${e.name}"'].join(', ')}.')
      ..writeln('// Change the environments and export again instead of editing this file by hand.')
      ..writeln('//')
      ..writeln('// A --dart-define value is compiled into the app and can be read back from the built binary, so nothing in here')
      ..writeln('// may be a real secret. Secret variables are empty placeholders: fetch the real value at run time.')
      ..writeln('//')
      ..writeln('// Run with a file of values:');
    for (final f in flavors) {
      b.writeln('//   flutter run --dart-define-from-file=${jsonPath(f)}${options.passFlavorArgument ? ' --flavor $f' : ''}');
    }
    b
      ..writeln()
      ..writeln('abstract final class AppConfig {')
      ..writeln('  /// Which flavor this build is for (FLAVOR).')
      ..writeln("  static const String flavor = String.fromEnvironment('$flavorDefine', defaultValue: ${dartString(first)});");
    for (final f in flavors) {
      final camel = getterName(f.replaceAll(RegExp(r'^[0-9]+'), ''));
      final name = 'is${camel[0].toUpperCase()}${camel.substring(1)}';
      b.writeln('  static bool get $name => flavor == ${dartString(f)};');
    }
    for (final k in keys) {
      final firstValue = values[first]![k.name]!;
      final useDefault = options.embedDefaults && !k.isSecret && firstValue.isNotEmpty;
      b.writeln();
      if (k.isSecret) {
        b
          ..writeln('  /// ${k.name}: a secret placeholder, empty on purpose. A --dart-define value is readable in the built app,')
          ..writeln('  /// so keep the real secret out of it.');
      } else {
        b.writeln('  /// ${k.name}, from the variable "${k.source}".');
      }
      switch (k.type) {
        case FlavorValueType.boolean:
          b.writeln("  static const bool ${k.getter} = bool.fromEnvironment('${k.name}'${useDefault ? ', defaultValue: $firstValue' : ''});");
        case FlavorValueType.integer:
          b.writeln("  static const int ${k.getter} = int.fromEnvironment('${k.name}'${useDefault ? ', defaultValue: $firstValue' : ''});");
        case FlavorValueType.url:
          b.writeln("  static const String ${k.getter} = String.fromEnvironment('${k.name}'${useDefault ? ', defaultValue: ${dartString(firstValue)}' : ''});");
          final uriName = k.getter.endsWith('Url') ? '${k.getter.substring(0, k.getter.length - 3)}Uri' : '${k.getter}Uri';
          b
            ..writeln('  /// [${k.getter}] as a [Uri].')
            ..writeln('  static Uri get $uriName => Uri.parse(${k.getter});');
        case FlavorValueType.string:
          b.writeln("  static const String ${k.getter} = String.fromEnvironment('${k.name}'${useDefault ? ', defaultValue: ${dartString(firstValue)}' : ''});");
      }
    }
    b.writeln('}');
    return b.toString();
  }
}
