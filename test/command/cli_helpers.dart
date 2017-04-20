import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/executable.dart';
import 'dart:io';


Future<ProcessResult> runPubGet(Directory workingDirectory,
    {bool offline: true}) async {
  var args = ["get", "--no-packages-dir"];
  if (offline) {
    args.add("--offline");
  }

  var result = await Process
      .run("pub", args,
      workingDirectory: workingDirectory.absolute.path, runInShell: true)
      .timeout(new Duration(seconds: 20));

  if (result.exitCode != 0) {
    throw new Exception("${result.stderr}");
  }

  return result;
}

void createTestProject(Directory source, Directory dest) {
  Process.runSync("cp", ["-r", "${source.path}", "${dest.path}"]);
}

Future<CLIResult> runAqueductProcess(
    List<String> commands, Directory workingDirectory) async {
  commands.add("--directory");
  commands.add("${workingDirectory.path}");

  var result = new CLIResult();
  var cmd = new Runner()
    ..outputSink = result.collectedOutput;
  var results = cmd.options.parse(commands);

  result.exitCode = await cmd.process(results);

  return result;
}

Directory getTestProjectDirectory(String name) {
  return new Directory.fromUri(Directory.current.uri
      .resolve("test/command/migration_test_projects/$name"));
}

class CLIResult {
  int exitCode;
  StringBuffer collectedOutput = new StringBuffer();
  String get output => collectedOutput.toString() ;
}