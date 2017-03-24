import 'dart:io';
import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'package:args/args.dart';
import 'package:aqueduct/executable.dart';
import '../helpers.dart';

void main() {
  /*
  Need to test that db_generate does what it is supposed to do
  And then tests on variations just on SchemaBuilder.sourceForSchemaUpgrade
   */
  group("Generating migration files", () {
    // This group handles checking the tool itself,
    // not the behavior of creating the appropriate migration file given schemas
    var projectSourceDirectory = getTestProjectDirectory("initial");
    Directory projectDirectory = new Directory("test_project");
    var migrationDirectory =
    new Directory.fromUri(projectDirectory.uri.resolve("migrations"));
    var addFiles = (List<String> filenames) {
      filenames.forEach((name) {
        new File.fromUri(migrationDirectory.uri.resolve(name))
            .writeAsStringSync(" ");
      });
    };

    setUp(() async {
      createTestProject(projectSourceDirectory, projectDirectory);
    });

    tearDown(() {
      projectDirectory.deleteSync(recursive: true);
    });

    test("Run without pub get yields error", () async {
      var out = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(out != 0, true);
    });

    test("Ensure migration directory will get created on generation", () async {
      await runPubGet(projectDirectory, offline: true);
      expect(migrationDirectory.existsSync(), false);
      var out = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(out, 0);
      expect(migrationDirectory.existsSync(), true);
    });

    test(
        "If there are no migration files, create an initial one that validates to schema",
            () async {
          await runPubGet(projectDirectory, offline: true);

          // Putting a non-migration file in there to ensure that this doesn't prevent from being ugpraded
          migrationDirectory.createSync();
          addFiles(["notmigration.dart"]);

          await runAqueductProcess(["db", "generate"], projectDirectory);
          var out = await runAqueductProcess(["db", "validate"], projectDirectory);
          expect(out, 0);
        });

    test("If there is already a migration file, create an upgrade file",
            () async {
          await runPubGet(projectDirectory, offline: true);

          await runAqueductProcess(["db", "generate"], projectDirectory);
          await runAqueductProcess(["db", "generate"], projectDirectory);

          expect(
              migrationDirectory
                  .listSync()
                  .where((fse) => !fse.uri.pathSegments.last.startsWith(".")),
              hasLength(2));
          expect(
              new File.fromUri(migrationDirectory.uri
                  .resolve("00000001_Initial.migration.dart"))
                  .existsSync(),
              true);
          expect(
              new File.fromUri(migrationDirectory.uri
                  .resolve("00000002_Unnamed.migration.dart"))
                  .existsSync(),
              true);

          var out = await runAqueductProcess(["db", "validate"], projectDirectory);
          expect(out, 0);
        });
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

Directory getTestProjectDirectory(String name) {
  return new Directory.fromUri(Directory.current.uri
      .resolve("test/command/migration_test_projects/$name"));
}
