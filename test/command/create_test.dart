import 'package:test/test.dart';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path_lib;

Directory testTemplateDirectory = new Directory("tmp_templates");

void main() {
  setUp(() {
    testTemplateDirectory.createSync();
  });

  tearDown(() {
    testTemplateDirectory.deleteSync(recursive: true);
  });

  group("Project naming", () {
    test("Appropriately named project gets created correctly", () {
      var res = runWith(["-n", "test_project"]);
      expect(res.exitCode, 0);

      expect(
          new Directory(
                  path_lib.join(testTemplateDirectory.path, "test_project"))
              .existsSync(),
          true);
    });

    test("Project name with bad characters fails immediately", () {
      var res = runWith(["-n", "!@"]);
      expect(res.exitCode, 1);

      expect(testTemplateDirectory.listSync().isEmpty, true);
    });

    test("Project name with uppercase characters fails immediately", () {
      var res = runWith(["-n", "ANeatApp"]);
      expect(res.exitCode, 1);

      expect(testTemplateDirectory.listSync().isEmpty, true);
    });

    test("Project name with dashes fails immediately", () {
      var res = runWith(["-n", "a-neat-app"]);
      expect(res.exitCode, 1);

      expect(testTemplateDirectory.listSync().isEmpty, true);
    });

    test("Not providing name returns error", () {
      var res = runWith([]);
      expect(res.exitCode, 1);

      expect(testTemplateDirectory.listSync().isEmpty, true);
    });

    test("Providing empty name returns error", () {
      var res = runWith(["-n"]);
      expect(res.exitCode, 255);

      expect(testTemplateDirectory.listSync().isEmpty, true);
    });
  });

  group("Templates from path", () {
    test("Template gets generated from local path, project points to it", () {
      var res = runWith(["-n", "test_project"]);
      expect(res.exitCode, 0);

      var aqueductLocationString =
          new File(projectPath("test_project", file: ".packages"))
              .readAsStringSync()
              .split("\n")
              .firstWhere((p) => p.startsWith("aqueduct:"))
              .split("aqueduct:")
              .last;

      var path = path_lib.normalize(path_lib.fromUri(aqueductLocationString));
      expect(path, path_lib.join(Directory.current.path, "lib"));
    });

    test("Tests run on template generated from local path", () {
      var res = runWith(["-n", "test_project"]);
      expect(res.exitCode, 0);

      res = Process.runSync("pub", ["run", "test", "-j", "1"],
          runInShell: true,
          workingDirectory:
              path_lib.join(testTemplateDirectory.path, "test_project"));
      expect(res.exitCode, 0);
      expect(res.stdout, contains("All tests passed"));
    });
  });
}

ProcessResult runWith(List<String> args) {
  var aqueductDirectory = Directory.current.path;
  var result = Process.runSync(
      "pub", ["global", "activate", "-spath", "$aqueductDirectory"],
      runInShell: true);
  expect(result.exitCode, 0);

  var allArgs = ["create", "--path-source", "$aqueductDirectory"];
  allArgs.addAll(args);
  return Process.runSync("aqueduct", allArgs,
      runInShell: true, workingDirectory: testTemplateDirectory.path);
}

String projectPath(String projectName, {String file}) {
  return path_lib.join(testTemplateDirectory.path, projectName, file);
}
