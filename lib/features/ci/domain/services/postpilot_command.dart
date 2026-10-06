// Pure Dart.
import '../entities/ci_options.dart';

/// Quoting for the shell commands the generated files contain.
abstract final class ShellQuote {
  static final _plain = RegExp(r'^[A-Za-z0-9_./:@%+=,-]+$');

  /// [text] as one POSIX shell word: left as it is when it needs no quotes, else in single quotes (a single quote
  /// inside becomes `'\''`). Nothing in single quotes is expanded, so the value cannot run anything.
  static String word(String text) => _plain.hasMatch(text) ? text : "'${text.replaceAll("'", r"'\''")}'";

  /// [text] as a YAML single-quoted scalar.
  static String yaml(String text) => "'${text.replaceAll("'", "''")}'";
}

/// What every generated setup runs: the PostPilot command line against the workspace, with the choices of the dialog.
abstract final class PostpilotCommand {
  static const repositoryName = 'ManzurulIslamBista/postpilot';
  static const repositoryUrl = 'https://github.com/$repositoryName';

  /// The file the JUnit report is written to.
  static const reportFile = 'report.xml';

  /// The file the Markdown summary is written to when an issue is to be opened from it.
  static const summaryFile = 'postpilot-summary.md';

  /// The arguments after `dart run bin/postpilot.dart`, grouped so a long command breaks between choices.
  /// [workspace] and [report] are shell words already (they contain a variable such as `"$GITHUB_WORKSPACE/..."`),
  /// so they are not quoted again; everything that came from the user is quoted here.
  static List<String> argumentGroups(CiOptions o, {required String workspace, required String report, String? summary}) {
    final env = o.environment;
    final collection = o.collection;
    return [
      'run $workspace',
      if (env != null && env.isNotEmpty) '--env ${ShellQuote.word(env)}',
      if (collection != null && collection.isNotEmpty) '--collection ${ShellQuote.word(collection)}',
      '--report junit --out $report',
      if (summary != null) '--markdown-out $summary',
      if (o.failOnSkip || o.bail || o.allowProduction)
        [if (o.failOnSkip) '--fail-on-skip', if (o.bail) '--bail', if (o.allowProduction) '--allow-production'].join(' '),
    ];
  }

  /// The whole command on one line.
  static String oneLine(CiOptions o, {required String workspace, required String report, String? summary}) =>
      'dart run bin/postpilot.dart ${argumentGroups(o, workspace: workspace, report: report, summary: summary).join(' ')}';

  /// The same command broken into lines with a trailing backslash, each line indented by [indent].
  static String wrapped(CiOptions o, {required String workspace, required String report, String? summary, String indent = ''}) {
    final groups = argumentGroups(o, workspace: workspace, report: report, summary: summary);
    final lines = ['dart run bin/postpilot.dart ${groups.first}', ...groups.skip(1)];
    return [
      for (final (i, line) in lines.indexed) '${i == 0 ? '' : '  '}$line${i == lines.length - 1 ? '' : r' \'}',
    ].map((l) => '$indent$l').join('\n');
  }

  /// The secrets as `name (the PostPilot variable ...)`, for a comment or a list.
  static List<String> secretLines(CiOptions o) => [
        for (final s in o.secrets) '${s.secretName}  (the value of the PostPilot variable ${s.variable})',
      ];
}
