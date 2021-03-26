// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:io';
import 'package:test/test.dart';
import 'cli_helpers.dart';

void main() {
  Terminal terminal;

  // This group handles checking the tool itself,
  // not the behavior of creating the appropriate migration file given schemas
  setUpAll(() async {
    terminal = await Terminal.createProject();
  });

  tearDownAll(Terminal.deleteTemporaryDirectory);

  setUp(() async {
    terminal.addOrReplaceFile("lib/application_test.dart", """
import 'package:aqueduct/aqueduct.dart';

class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int id;

  String foo;
}
      """);
    terminal.clearOutput();
    if (terminal.defaultMigrationDirectory.existsSync()) {
      terminal.defaultMigrationDirectory.deleteSync(recursive: true);
    }
  });

  test("Run without pub get yields error", () async {
    var res = await terminal.runAqueductCommand("db", ["generate"]);
    expect(res, isNot(0));
  });

  test("Ensure migration directory will get created on generation", () async {
    await terminal.getDependencies(offline: true);

    expect(terminal.defaultMigrationDirectory.existsSync(), false);
    var res = await terminal.runAqueductCommand("db", ["generate"]);
    expect(res, 0);
    expect(terminal.defaultMigrationDirectory.existsSync(), true);
  });

  test(
      "If there are no migration files, create an initial one that validates to schema",
      () async {
    await terminal.getDependencies(offline: true);

    // Putting a non-migration file in there to ensure that this doesn't prevent from being ugpraded
    terminal.defaultMigrationDirectory.createSync();
    terminal.addOrReplaceFile("migrations/notmigration.dart", " ");

    var res = await terminal.runAqueductCommand("db", ["generate"]);
    expect(res, 0);
    terminal.clearOutput();

    res = await terminal.runAqueductCommand("db", ["validate"]);
    expect(res, 0);
  });

  test(
      "If there is already a migration file, create an upgrade file with changes",
      () async {
    await terminal.getDependencies(offline: true);

    var res = await terminal.runAqueductCommand("db", ["generate"]);
    expect(res, 0);
    terminal.clearOutput();

    // Let's add an index
    terminal.modifyFile("lib/application_test.dart", (prev) {
      return prev.replaceFirst(
          "String foo;", "@Column(indexed: true) String foo;");
    });

    res = await terminal.runAqueductCommand("db", ["generate"]);
    expect(res, 0);
    terminal.clearOutput();

    expect(
        terminal.defaultMigrationDirectory
            .listSync()
            .where((fse) => !fse.uri.pathSegments.last.startsWith(".")),
        hasLength(2));
    expect(
        File.fromUri(terminal.defaultMigrationDirectory.uri
                .resolve("00000001_initial.migration.dart"))
            .existsSync(),
        true);
    expect(
        File.fromUri(terminal.defaultMigrationDirectory.uri
                .resolve("00000002_unnamed.migration.dart"))
            .existsSync(),
        true);

    res = await terminal.runAqueductCommand("db", ["validate"]);
    expect(res, 0);
  });

  test("Can specify migration directory other than default, relative path",
      () async {
    await terminal.getDependencies(offline: true);

    var res = await terminal.runAqueductCommand(
        "db", ["generate", "--migration-directory", "foobar"]);
    expect(res, 0);

    final migDir =
        Directory.fromUri(terminal.workingDirectory.uri.resolve("foobar/"));
    final files = migDir.listSync();
    expect(
        files.any((fse) => fse is File && fse.path.endsWith("migration.dart")),
        true);
  });

  test("Can specify migration directory other than default, absolute path",
      () async {
    await terminal.getDependencies(offline: true);

    final migDir =
        Directory.fromUri(terminal.workingDirectory.uri.resolve("foobar/"));
    var res = await terminal.runAqueductCommand("db", [
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
    await terminal.getDependencies(offline: true);
    var res = await terminal.runAqueductCommand("db", ["generate"]);
    expect(res, 0);
    terminal.clearOutput();

    terminal.modifyFile("lib/application_test.dart", (prev) {
      return prev.replaceFirst("String foo;", "String foo;\nString bar;");
    });
    res = await terminal.runAqueductCommand("db", ["generate"]);
    expect(res, 0);

    expect(terminal.output, contains("may fail"));
    expect(terminal.output, contains("\"_TestObject\""));
    expect(terminal.output, contains("\"bar\""));
  });
}
