import 'dart:async';
import 'dart:io';

import 'package:runtime/runtime.dart';

Future main(List<String> args) async {
  final blacklist = [
    (String s) => s.contains("test/command/"),
    (String s) => s.contains("/compilation_errors/"),
    (String s) => s.contains("test/openapi/"),
    (String s) => s.contains("postgresql/migration/"),
    (String s) => s.contains("db/migration/"),
    (String s) => s.endsWith("entity_mirrors_test.dart"),
    (String s) => s.endsWith("moc_openapi_test.dart"),
  ];

  List<File> testFiles;

  if (args.length == 1) {
    testFiles = [File(args.first)];
  } else {
    final testDir = args.isNotEmpty
        ? Directory.current.uri.resolveUri(Uri.parse(args[0]))
        : Directory.current.uri.resolve("test/");

    testFiles = Directory.fromUri(testDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith("_test.dart"))
        .where((f) => blacklist.every(
            (blacklistFunction) => blacklistFunction(f.uri.path) == false))
        .toList();
  }
  var remainingCounter = testFiles.length;
  var passCounter = 0;
  var failCounter = 0;
  for (File f in testFiles) {
    final makePrompt = () =>
        "(Pass: $passCounter Fail: $failCounter Remain: $remainingCounter)";
    print("${makePrompt()} Loading test ${f.path}...");
    final ctx = BuildContext(
        Directory.current.uri.resolve("lib/").resolve("aqueduct.dart"),
        Directory.current.uri.resolve("_build/"),
        Directory.current.uri.resolve("run"),
        f.readAsStringSync(),
        forTests: true);
    final bm = BuildManager(ctx);
    await bm.build();

    print("${makePrompt()} Running tests derived from ${f.path}...");
    final result = await Process.start("dart", ["test/main_test.dart"],
        workingDirectory:
            ctx.buildDirectoryUri.toFilePath(windows: Platform.isWindows));
    stdout.addStream(result.stdout);
    stderr.addStream(result.stderr);

    if (await result.exitCode != 0) {
      exitCode = -1;
      failCounter++;
      print("Tests FAILED in ${f.path}.");
    } else {
      passCounter++;
    }
    print("${makePrompt()} Completed tests derived from ${f.path}.");
//    await bm.clean();
    remainingCounter--;
  }
}
