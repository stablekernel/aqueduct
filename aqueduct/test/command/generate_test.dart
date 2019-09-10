// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:io';
import 'package:terminal/terminal.dart';
import 'package:test/test.dart';
import 'cli_helpers.dart';

void main() {
  CLIClient templateCli;
  CLIClient projectUnderTestCli;

  setUpAll(() async {
    templateCli = await CLIClient(Terminal(ProjectTerminal.projectsDirectory)).createProject();
    await templateCli.terminal.getDependencies(offline: true);
  });

  tearDownAll(ProjectTerminal.tearDownAll);

  setUp(() async {
    projectUnderTestCli = templateCli.replicate(Uri.parse("replica/"));
    projectUnderTestCli.projectTerminal.addLibraryFile("application_test", """
import 'package:aqueduct/aqueduct.dart';
    
class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int id;

  String foo;
}
      """);
  });


  tearDown(() {
    projectUnderTestCli.delete();
  });

  test("Run without pub get yields error", () async {
    File.fromUri(projectUnderTestCli.terminal.workingDirectory.uri.resolve("pubspec.lock")).deleteSync();
    File.fromUri(projectUnderTestCli.terminal.workingDirectory.uri.resolve(".packages")).deleteSync();

    var res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, isNot(0));
  });

  test("Ensure migration directory will get created on generation", () async {
    expect(projectUnderTestCli.defaultMigrationDirectory.existsSync(), false);
    var res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, 0);
    expect(projectUnderTestCli.defaultMigrationDirectory.existsSync(), true);
  });

  test(
      "If there are no migration files, create an initial one that validates to schema",
      () async {
    // Putting a non-migration file in there to ensure that this doesn't prevent from being ugpraded
        projectUnderTestCli.defaultMigrationDirectory.createSync();
        projectUnderTestCli.terminal.addOrReplaceFile("migrations/notmigration.dart", " ");

    var res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, 0);
    projectUnderTestCli.clearOutput();

    res = await projectUnderTestCli.run("db", ["validate"]);
    expect(res, 0);
  });

  test(
      "If there is already a migration file, create an upgrade file with changes",
      () async {
    var res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, 0);
    projectUnderTestCli.clearOutput();

    // Let's add an index
    projectUnderTestCli.terminal.modifyFile("lib/application_test.dart", (prev) {
      return prev.replaceFirst(
          "String foo;", "@Column(indexed: true) String foo;");
    });

    res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, 0);
    projectUnderTestCli.clearOutput();

    expect(
        projectUnderTestCli.defaultMigrationDirectory
            .listSync()
            .where((fse) => !fse.uri.pathSegments.last.startsWith(".")),
        hasLength(2));
    expect(
        File.fromUri(projectUnderTestCli.defaultMigrationDirectory.uri
                .resolve("00000001_initial.migration.dart"))
            .existsSync(),
        true);
    expect(
        File.fromUri(projectUnderTestCli.defaultMigrationDirectory.uri
                .resolve("00000002_unnamed.migration.dart"))
            .existsSync(),
        true);

    res = await projectUnderTestCli.run("db", ["validate"]);
    expect(res, 0);
  });

  test("Can specify migration name other than default", () async {
    var res = await projectUnderTestCli.run("db", ["generate", "--name", "InitializeDatabase"]);
    expect(res, 0);
    projectUnderTestCli.clearOutput();

    // Let's add an index
    projectUnderTestCli.terminal.modifyFile("lib/application_test.dart", (prev) {
      return prev.replaceFirst(
          "String foo;", "@Column(indexed: true) String foo;");
    });

    res = await projectUnderTestCli.run("db", ["generate", "--name", "add_index"]);
    expect(res, 0);
    projectUnderTestCli.clearOutput();

    expect(
      projectUnderTestCli.defaultMigrationDirectory
            .listSync()
            .where((fse) => !fse.uri.pathSegments.last.startsWith(".")),
        hasLength(2));
    expect(
        File.fromUri(projectUnderTestCli.defaultMigrationDirectory.uri
                .resolve("00000001_initialize_database.migration.dart"))
            .existsSync(),
        true);
    expect(
        File.fromUri(projectUnderTestCli.defaultMigrationDirectory.uri
                .resolve("00000002_add_index.migration.dart"))
            .existsSync(),
        true);

    res = await projectUnderTestCli.run("db", ["validate"]);
    expect(res, 0);
  });

  test("Can specify migration directory other than default, relative path",
      () async {
    var res = await projectUnderTestCli.run(
        "db", ["generate", "--migration-directory", "foobar"]);
    expect(res, 0);

    final migDir =
        Directory.fromUri(projectUnderTestCli.terminal.workingDirectory.uri.resolve("foobar/"));
    final files = migDir.listSync();
    expect(
        files.any((fse) => fse is File && fse.path.endsWith("migration.dart")),
        true);
  });

  test("Can specify migration directory other than default, absolute path",
      () async {
    final migDir =
        Directory.fromUri(projectUnderTestCli.terminal.workingDirectory.uri.resolve("foobar/"));
    var res = await projectUnderTestCli.run("db", [
      "generate",
      "--migration-directory",
      migDir.uri.toFilePath(windows: Platform.isWindows)
    ]);
    expect(res, 0);

    final files = migDir.listSync();
    expect(
        files.any((fse) => fse is File && fse.path.endsWith("migration.dart")),
        true);
  });

  test("If migration file requires additional input, send message to user",
      () async {
    var res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, 0);
    projectUnderTestCli.clearOutput();

    projectUnderTestCli.terminal.modifyFile("lib/application_test.dart", (prev) {
      return prev.replaceFirst("String foo;", "String foo;\nString bar;");
    });
    res = await projectUnderTestCli.run("db", ["generate"]);
    expect(res, 0);

    expect(projectUnderTestCli.output, contains("may fail"));
    expect(projectUnderTestCli.output, contains("\"_TestObject\""));
    expect(projectUnderTestCli.output, contains("\"bar\""));
  });
}
