import 'dart:io';
import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'cli_helpers.dart';

void main() {
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
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, isNot(0));
    });

    test("Ensure migration directory will get created on generation", () async {
      await runPubGet(projectDirectory, offline: true);
      expect(migrationDirectory.existsSync(), false);
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      print("${res.output}");
      expect(res.exitCode, 0);
      expect(migrationDirectory.existsSync(), true);
    });

    test(
        "If there are no migration files, create an initial one that validates to schema",
        () async {
      await runPubGet(projectDirectory, offline: true);

      // Putting a non-migration file in there to ensure that this doesn't prevent from being ugpraded
      migrationDirectory.createSync();
      addFiles(["notmigration.dart"]);

      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      res = await runAqueductProcess(["db", "validate"], projectDirectory);
      expect(res.exitCode, 0);
    });

    test(
        "If there is already a migration file, create an upgrade file with changes",
        () async {
      await runPubGet(projectDirectory, offline: true);

      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      // Let's add an index
      var modelFile = new File.fromUri(
          projectDirectory.uri.resolve("lib/").resolve("wildfire.dart"));
      var contents = modelFile.readAsStringSync().replaceFirst(
          "String foo;", "@ManagedColumnAttributes(indexed: true) String foo;");
      modelFile.writeAsStringSync(contents);

      res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

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

      res = await runAqueductProcess(["db", "validate"], projectDirectory);
      expect(res.exitCode, 0);
    });
  });
}

Future writeMigrations(
    Directory migrationDirectory, List<Schema> schemas) async {
  var currentNumberOfMigrations = migrationDirectory
      .listSync()
      .where((e) => e.path.endsWith("migration.dart"))
      .length;

  for (var i = 1; i < schemas.length; i++) {
    var source = MigrationBuilder.sourceForSchemaUpgrade(
        schemas[i - 1], schemas[i], i);

    var file = new File.fromUri(migrationDirectory.uri
        .resolve("${i + currentNumberOfMigrations}.migration.dart"));
    file.writeAsStringSync(source);
  }
}

Future addMigrationFileWithLines(Directory projectDirectory, List<String> lines) async {
  var migDir = new Directory.fromUri(projectDirectory.uri.resolve("migrations/"));
  var migFiles = migDir.listSync(recursive: false).where((fse) => fse.path.endsWith(".migration.dart")).toList();
  var version = migFiles.length + 1;
  var emptyContents = MigrationBuilder.sourceForSchemaUpgrade(new Schema([]), new Schema([]), version);
  emptyContents = emptyContents.split("\n")
      .map((line) {
        if (line.contains("Future upgrade()")) {
          var l = [line];
          l.addAll(lines);
          return l;
        }
        return [line];
      })
      .expand((ls) => ls)
      .join("\n");

  var emptyFile = new File.fromUri(migDir.uri.resolve("$version.migration.dart"));
  emptyFile.writeAsString(emptyContents);
}
