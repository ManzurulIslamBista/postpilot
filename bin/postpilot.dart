import 'dart:io';
import 'package:postpilot/features/cli/cli_main.dart';

/// `dart run bin/postpilot.dart run workspace.json --env Staging --report junit --out report.xml`
/// `dart run bin/postpilot.dart proxy` starts the CORS proxy the web version uses (see `proxy --help`).
Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
