import 'dart:io';
import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/executable.dart';
import 'package:http/http.dart' as http;

import '../helpers.dart';

void main() {
  var temporaryDirectory = new Directory("test_project");
  var testDirectory =
      new Directory.fromUri(Directory.current.uri.resolve("test"));
  var commandDirectory =
      new Directory.fromUri(testDirectory.uri.resolve("command"));
  var sourceDirectory =
      new Directory.fromUri(commandDirectory.uri.resolve("serve_test_project"));


  tearDown(() async {
    await runAqueductProcess(["serve", "stop"], temporaryDirectory);
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    createTestProject(sourceDirectory, temporaryDirectory);
    await runPubGet(temporaryDirectory, offline: true);
  });

  test("Served application starts and responds to route", () async {
    var res = await runAqueductProcess(["serve", "--detached"], temporaryDirectory);
    expect(res, 0);

    var result = await http.get("http://localhost:8080/endpoint");
    expect(result.statusCode, 200);
  });

  test("Ensure we don't find the base RequestSink class", () async {
    var libDir = new Directory.fromUri(temporaryDirectory.uri.resolve("lib"));
    var libFile = new File.fromUri(libDir.uri.resolve("wildfire.dart"));
    libFile.writeAsStringSync("import 'package:aqueduct/aqueduct.dart';");

    var res = await runAqueductProcess(["serve"], temporaryDirectory);
    expect(res != 0, true);
  });
}

Future<int> runAqueductProcess(
    List<String> commands, Directory workingDirectory) async {
  commands.add("--directory");
  commands.add("${workingDirectory.path}");

  var cmd = new Runner();
  var results = cmd.options.parse(commands);

  return cmd.process(results);
}
