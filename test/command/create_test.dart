import 'dart:io';
import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/executable.dart';
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
      expect(res, 0);

      expect(new Directory(path_lib.join(temporaryDirectory.path)).existsSync(),
          true);
    });

    test("Project name with bad characters fails immediately", () async {
      var res = await runWith(["!@"]);
      expect(res != 0, true);

      expect(temporaryDirectory.existsSync(), false);
    });

    test("Project name with uppercase characters fails immediately", () async {
      var res = await runWith(["ANeatApp"]);
      expect(res != 0, true);

      expect(temporaryDirectory.existsSync(), false);
    });

    test("Project name with dashes fails immediately", () async {
      expect(await runWith(["a-neat-app"]) != 0, true);
      expect(temporaryDirectory.existsSync(), false);
    });

    test("Not providing name returns error", () async {
      expect(await runWith([]) != 0, true);
      expect(temporaryDirectory.existsSync(), false);
    });
  });

  group("Templates from path", () {
    test("Template gets generated from local path, project points to it",
        () async {
      expect(await runWith(["test_project"]), 0);

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

    test("Tests run on template generated from local path", () async {
      expect(await runWith(["test_project"]), 0);

      var res = Process.runSync("pub", ["run", "test", "-j", "1"],
          runInShell: true, workingDirectory: temporaryDirectory.path);

      expect(res.exitCode, 0);
      expect(res.stdout, contains("All tests passed"));
    });
  });
}

Future<int> runWith(List<String> args) {
  var aqueductDirectory = Directory.current.path;
  var allArgs = ["create", "--path-source", "$aqueductDirectory"];
  allArgs.addAll(args);

  var cmd = new Runner();
  var results = cmd.options.parse(allArgs);

  return cmd.process(results);
}
