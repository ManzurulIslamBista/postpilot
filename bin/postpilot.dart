import 'dart:io';
import 'package:postpilot/features/cli/cli_main.dart';

/// `dart run bin/postpilot.dart run workspace.json --env Staging --report junit --out report.xml`
Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
