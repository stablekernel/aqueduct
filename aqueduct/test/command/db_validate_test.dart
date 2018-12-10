// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:io';

import 'package:test/test.dart';

import 'cli_helpers.dart';

void main() {
  group("Validating", () {
    Terminal terminal;

    setUp(() async {
      terminal = await Terminal.createProject();
      terminal.addOrReplaceFile("lib/application_test.dart", """
class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int id;

  String foo;
}
      """);
      await terminal.getDependencies(offline: true);
    });

    tearDown(Terminal.deleteTemporaryDirectory);

    test("If validating with no migration dir, get error", () async {
      var res = await terminal.runAqueductCommand("db", ["validate"]);

      expect(res, isNot(0));
      expect(terminal.output, contains("No migration files found"));
    });

    test("Validating two equal schemas succeeds", () async {
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      res = await terminal.runAqueductCommand("db", ["validate"]);
      expect(res, 0);
      expect(terminal.output, contains("Validation OK"));
      expect(terminal.output, contains("version is 1"));
    });

    test("Validating different schemas fails", () async {
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      terminal.modifyFile("migrations/00000001_initial.migration.dart",
          (contents) {
        const upgradeLocation = "upgrade()";
        final nextLine =
            contents.indexOf("\n", contents.indexOf(upgradeLocation));
        return contents.replaceRange(nextLine, nextLine + 1, """
        database.createTable(SchemaTable(\"foo\", []));
        """);
      });

      res = await terminal.runAqueductCommand("db", ["validate"]);
      expect(res, isNot(0));
      expect(terminal.output, contains("Validation failed"));
    });

    test(
        "Validating runs all migrations in directory and checks the total product",
        () async {
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      terminal.modifyFile("migrations/00000001_initial.migration.dart",
          (contents) {
        const upgradeLocation = "upgrade()";
        final nextLine =
            contents.indexOf("\n", contents.indexOf(upgradeLocation));
        return contents.replaceRange(nextLine, nextLine + 1, """
        database.createTable(SchemaTable(\"foo\", []));
        """);
      });

      res = await terminal.runAqueductCommand("db", ["validate"]);
      expect(res, isNot(0));
      expect(terminal.output, contains("Validation failed"));

      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      var secondMigrationFile = File.fromUri(terminal
          .defaultMigrationDirectory.uri
          .resolve("00000002_unnamed.migration.dart"));
      expect(secondMigrationFile.readAsStringSync(),
          contains("database.deleteTable(\"foo\")"));

      res = await terminal.runAqueductCommand("db", ["validate"]);
      expect(res, 0);
    });
  });
}
