import 'dart:io';
import 'dart:async';

import 'package:test/test.dart';
import 'cli_helpers.dart';
import 'package:path/path.dart' as path_lib;

var temporaryDirectory =
    new Directory.fromUri(Directory.current.uri.resolve("test_project"));

void main() {
  setUp(() {});

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  group("Project naming", () {
    test("Appropriately named project gets created correctly", () async {
      var res = await runWith(["test_project"]);
      expect(res.exitCode, 0);

      expect(new Directory(path_lib.join(temporaryDirectory.path)).existsSync(),
          true);
    });

    test("Project name with bad characters fails immediately", () async {
      var res = await runWith(["!@"]);
      expect(res.exitCode, isNot(0));
      expect(res.output, contains("Invalid project name"));
      expect(res.output, contains("snake_case"));

      expect(temporaryDirectory.existsSync(), false);
    });

    test("Project name with uppercase characters fails immediately", () async {
      var res = await runWith(["ANeatApp"]);
      expect(res.exitCode, isNot(0));
      expect(res.output, contains("Invalid project name"));
      expect(res.output, contains("snake_case"));

      expect(temporaryDirectory.existsSync(), false);
    });

    test("Project name with dashes fails immediately", () async {
      var res = await runWith(["a-neat-app"]);
      expect(res.exitCode, isNot(0));
      expect(res.output, contains("Invalid project name"));
      expect(res.output, contains("snake_case"));

      expect(temporaryDirectory.existsSync(), false);
    });

    test("Not providing name returns error", () async {
      var res = await runWith([]);
      expect(res.exitCode, isNot(0));
    });
  });

  group("Templates", () {
    test("Listed templates are accurate", () async {
      // This test will fail if you add or change the name of a template.
      // If you are adding a template, just add it to this list. If you are renaming/deleting a template,
      // make sure there is still a 'default' template.
      var result = await runWith(["list-templates"]);
      var names = ["db", "db_and_auth", "default"];
      var lines = result.output.split("\n");

      // [0;1m-- Aqueduct CLI Version: 2.1.1[0m
      // [0;1m-- Available templates:[0m
      // [0m    [0m
      // [0m    default - an empty Aqueduct application[0m
      // [0m    db - an Aqueduct application with a database connection and data model[0m
      // [0m    db_and_auth - an Aqueduct application with a database connection, data model and OAuth 2.0 endpoints[0m
      //

      expect(lines.length, names.length + 4);
      for (var n in names) {
        expect(lines.any((l) => l.startsWith("\x1B[0m    $n ")), true);
      }
    });

    test("Template gets generated from local path, project points to it",
        () async {
      var res = await runWith(["test_project"]);
      expect(res.exitCode, 0);

      var aqueductLocationString =
          new File.fromUri(temporaryDirectory.uri.resolve(".packages"))
              .readAsStringSync()
              .split("\n")
              .firstWhere((p) => p.startsWith("aqueduct:"))
              .split("aqueduct:")
              .last;

      var path = path_lib.normalize(path_lib.fromUri(aqueductLocationString));
      expect(path, path_lib.join(Directory.current.path, "lib"));
    });

    test("Tests run on template generated from local path (with a little help)", () async {
      expect((await runWith(["test_project", "-t", "db"])).exitCode, 0);

      var res = Process.runSync("pub", ["run", "test", "-j", "1"],
          runInShell: true, workingDirectory: temporaryDirectory.path);

      expect(res.exitCode, 0);
      expect(res.stdout, contains("All tests passed"));
    });
  });
}

Future<CLIResult> runWith(List<String> args) {
  var aqueductDirectory = Directory.current.path;
  var allArgs = ["create", "--path-source", "$aqueductDirectory"];
  allArgs.addAll(args);

  return runAqueductProcess(allArgs, Directory.current);
}

void addLinesToFile(
    File file, String afterFindingThisString, String insertThisString) {
  var contents = file.readAsStringSync();
  var indexOf =
      contents.indexOf(afterFindingThisString) + afterFindingThisString.length;
  var newContents = contents.replaceRange(indexOf, indexOf, insertThisString);
  file.writeAsStringSync(newContents);
}
