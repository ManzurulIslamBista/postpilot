// Type-checks generated Dart in a throw-away package, offline: the packages it needs are taken from
// the pub cache of this machine (never the network), the Dart SDK is the one Flutter ships, and the
// analyzer runs in this process. `dart pub get` and `dart analyze` are not used (they do not run
// reliably here), so the package_config.json is written by hand from what is on disk.
//
// A package that is not in the cache cannot be checked against: the caller says so (or supplies a
// stand-in, which only proves that the rest of a file compiles).
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final class PackageCheckResult {
  /// `path: message` for every error or warning the analyzer reported, and every lint for the paths in `lintPaths`.
  final List<String> problems;

  /// Why nothing could be checked (a package or the SDK is missing); null when the check ran.
  final String? skippedBecause;

  /// What the packages resolved to, for the test's own report.
  final Map<String, String> resolved;

  const PackageCheckResult({this.problems = const [], this.skippedBecause, this.resolved = const {}});
}

/// Packages the offline check prefers a specific cached version of, because a newer one would not fit the
/// `test_api` that `flutter_test` pins in this project.
const _preferred = {'test': '1.31.0', 'test_core': '0.6.17', 'mocktail': '1.0.5'};

Directory? _pubCacheHosted() {
  final env = Platform.environment;
  final candidates = [
    if (env['PUB_CACHE'] != null) p.join(env['PUB_CACHE']!, 'hosted', 'pub.dev'),
    if (env['LOCALAPPDATA'] != null) p.join(env['LOCALAPPDATA']!, 'Pub', 'Cache', 'hosted', 'pub.dev'),
    if (env['APPDATA'] != null) p.join(env['APPDATA']!, 'Pub', 'Cache', 'hosted', 'pub.dev'),
    if (env['HOME'] != null) p.join(env['HOME']!, '.pub-cache', 'hosted', 'pub.dev'),
    if (env['USERPROFILE'] != null) p.join(env['USERPROFILE']!, '.pub-cache', 'hosted', 'pub.dev'),
  ];
  for (final c in candidates) {
    final dir = Directory(c);
    if (dir.existsSync()) return dir;
  }
  return null;
}

/// The Dart SDK inside the Flutter SDK that runs this test.
String? _dartSdk() {
  final roots = <String>[];
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) roots.add(flutterRoot);
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    roots.add(dir.path);
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  for (final root in roots) {
    final sdk = p.join(root, 'bin', 'cache', 'dart-sdk');
    if (Directory(p.join(sdk, 'lib', '_internal')).existsSync()) return sdk;
  }
  return null;
}

List<int> _version(String text) => [for (final part in text.split(RegExp(r'[.+-]'))) int.tryParse(part) ?? 0];

int _compare(String a, String b) {
  final x = _version(a);
  final y = _version(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}

/// The highest release of [name] in [cache] (a pre-release is used only when nothing else exists).
({String version, Directory dir})? _cached(Directory cache, String name) {
  final preferred = _preferred[name];
  final found = <String, Directory>{};
  for (final entry in cache.listSync()) {
    if (entry is! Directory) continue;
    final base = p.basename(entry.path);
    if (!base.startsWith('$name-')) continue;
    final version = base.substring(name.length + 1);
    if (!RegExp(r'^\d+\.\d+\.\d+').hasMatch(version)) continue; // `foo_bar-1.0.0` also starts with `foo-` only when the name is a prefix
    found[version] = entry;
  }
  if (found.isEmpty) return null;
  if (preferred != null && found.containsKey(preferred)) return (version: preferred, dir: found[preferred]!);
  final releases = found.keys.where((v) => !v.contains('-')).toList()..sort(_compare);
  final all = releases.isNotEmpty ? releases : (found.keys.toList()..sort(_compare));
  return (version: all.last, dir: found[all.last]!);
}

/// Dependencies a cached package declares (not dev dependencies, not SDK packages).
List<String> _dependenciesOf(Directory dir) {
  final file = File(p.join(dir.path, 'pubspec.yaml'));
  if (!file.existsSync()) return const [];
  try {
    final yaml = loadYaml(file.readAsStringSync());
    final deps = yaml is Map ? yaml['dependencies'] : null;
    if (deps is! Map) return const [];
    return [
      for (final e in deps.entries)
        if (!(e.value is Map && (e.value as Map).containsKey('sdk'))) '${e.key}',
    ];
  } catch (_) {
    return const [];
  }
}

/// Writes [files] (relative path to text) as the package [packageName] below [root], and returns what the
/// analyzer finds in it. [directDependencies] are the packages the generated code imports; those found
/// neither in this project's package config nor in the pub cache come from [standIns] (name to the text of
/// its single library) or make the check report that it was skipped.
Future<PackageCheckResult> checkGeneratedPackage({
  required Directory root,
  required String packageName,
  required Map<String, String> files,
  required List<String> directDependencies,
  Map<String, String> standIns = const {},
  Set<String> lintPaths = const {},
}) async {
  final cache = _pubCacheHosted();
  if (cache == null) return const PackageCheckResult(skippedBecause: 'the pub cache was not found');
  final sdk = _dartSdk();
  if (sdk == null) return const PackageCheckResult(skippedBecause: 'the Dart SDK of this Flutter installation was not found');
  final configFile = File(p.join(Directory.current.path, '.dart_tool', 'package_config.json'));
  if (!configFile.existsSync()) return const PackageCheckResult(skippedBecause: 'the project has no .dart_tool/package_config.json (run pub get)');

  // What this project already resolved: the closure of flutter_test, dio, ... with absolute locations.
  final known = <String, ({String root, String packageUri, String? language})>{};
  final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  for (final package in (config['packages'] as List).cast<Map<String, dynamic>>()) {
    final uri = configFile.uri.resolve(package['rootUri'] as String);
    known['${package['name']}'] = (root: p.fromUri(uri), packageUri: '${package['packageUri'] ?? 'lib/'}', language: package['languageVersion'] as String?);
  }

  final resolved = <String, String>{};
  final entries = <String, ({String root, String packageUri, String? language})>{};
  final missing = <String>[];
  void need(String name) {
    if (entries.containsKey(name)) return;
    if (standIns.containsKey(name)) {
      entries[name] = (root: p.join(root.path, '.stand_ins', name), packageUri: 'lib/', language: '3.0');
      resolved[name] = 'stand-in';
      return;
    }
    final fromProject = known[name];
    final fromCache = _cached(cache, name);
    // The cached copy wins only for packages the project does not have, or that the offline check pins.
    if (_preferred.containsKey(name) && fromCache != null) {
      entries[name] = (root: fromCache.dir.path, packageUri: 'lib/', language: '3.0');
      resolved[name] = fromCache.version;
      for (final dep in _dependenciesOf(fromCache.dir)) {
        need(dep);
      }
      return;
    }
    if (fromProject != null) {
      entries[name] = fromProject;
      resolved[name] = p.basename(fromProject.root).replaceFirst('$name-', '');
      return;
    }
    if (fromCache != null) {
      entries[name] = (root: fromCache.dir.path, packageUri: 'lib/', language: '3.0');
      resolved[name] = fromCache.version;
      for (final dep in _dependenciesOf(fromCache.dir)) {
        need(dep);
      }
      return;
    }
    missing.add(name);
  }

  for (final name in directDependencies) {
    need(name);
  }
  if (missing.isNotEmpty) {
    return PackageCheckResult(skippedBecause: 'not in the pub cache: ${missing.join(', ')}');
  }
  // Lints are read from flutter_lints when the project has it.
  final withLints = known.containsKey('flutter_lints') && known.containsKey('lints');
  if (withLints) {
    entries['flutter_lints'] = known['flutter_lints']!;
    entries['lints'] = known['lints']!;
  }

  // The package itself.
  if (root.existsSync()) root.deleteSync(recursive: true);
  root.createSync(recursive: true);
  entries[packageName] = (root: root.path, packageUri: 'lib/', language: '3.8');
  for (final entry in files.entries) {
    File(p.join(root.path, entry.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  standIns.forEach((name, text) {
    File(p.join(root.path, '.stand_ins', name, 'lib', '$name.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  });
  final pubspec = StringBuffer('name: $packageName\npublish_to: none\nenvironment:\n  sdk: ^3.8.0\ndependencies:\n');
  for (final name in directDependencies) {
    if (standIns.containsKey(name)) {
      pubspec.writeln('  $name:\n    path: .stand_ins/$name');
    } else {
      pubspec.writeln('  $name: ^${resolved[name]}');
    }
  }
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec.toString());
  if (withLints) File(p.join(root.path, 'analysis_options.yaml')).writeAsStringSync('include: package:flutter_lints/flutter.yaml\n');

  final packages = [
    for (final e in entries.entries)
      {
        'name': e.key,
        'rootUri': Uri.directory(e.value.root).toString(),
        'packageUri': e.value.packageUri,
        if (e.value.language != null) 'languageVersion': e.value.language,
      },
  ];
  File(p.join(root.path, '.dart_tool', 'package_config.json'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode({'configVersion': 2, 'packages': packages}));

  final collection = AnalysisContextCollection(includedPaths: [root.path], sdkPath: sdk);
  final problems = <String>[];
  try {
    for (final relative in files.keys.where((f) => f.endsWith('.dart'))) {
      final path = p.normalize(p.join(root.path, relative));
      final result = await collection.contextFor(path).currentSession.getErrors(path);
      if (result is! ErrorsResult) {
        problems.add('$relative: could not be analyzed (${result.runtimeType})');
        continue;
      }
      for (final d in result.diagnostics) {
        final severity = d.severity.name;
        final isLint = severity == 'info';
        if (isLint && !lintPaths.any(relative.startsWith)) continue;
        problems.add('$relative:${result.lineInfo.getLocation(d.offset).lineNumber}: $severity ${d.diagnosticCode.lowerCaseName}: ${d.message}');
      }
    }
  } finally {
    await collection.dispose();
  }
  return PackageCheckResult(problems: problems, resolved: resolved);
}
