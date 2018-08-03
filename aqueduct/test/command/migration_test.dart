// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/mixins/database_managing.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'cli_helpers.dart';

void main() {
  justLogEverything();
  group("Cooperation", () {
    PersistentStore store;

    setUp(() {
      store = PostgreSQLPersistentStore(
          "dart", "dart", "localhost", 5432, "dart_test");
    });

    tearDown(() async {
      await store.close();
    });

    test(
        "Migration subclasses can be executed and commands are generated and executed on the DB, schema is udpated",
        () async {
      // Note that the permutations of operations are covered in different tests, this is just to ensure that
      // executing a migration/upgrade all work together.
      var schema = Schema([
        SchemaTable("tableToKeep", [
          SchemaColumn("columnToEdit", ManagedPropertyType.string),
          SchemaColumn("columnToDelete", ManagedPropertyType.integer)
        ]),
        SchemaTable("tableToDelete",
            [SchemaColumn("whocares", ManagedPropertyType.integer)]),
        SchemaTable("tableToRename",
            [SchemaColumn("whocares", ManagedPropertyType.integer)])
      ]);

      var initialBuilder =
          SchemaBuilder.toSchema(store, schema, isTemporary: true);
      for (var cmd in initialBuilder.commands) {
        await store.execute(cmd);
      }

      var mig = Migration1();
      mig.version = 1;
      final outSchema = await store.upgrade(schema, [mig], temporary: true);

      // 'Sync up' that schema to compare it
      final tableToKeep = schema.tableForName("tableToKeep");
      tableToKeep.addColumn(SchemaColumn(
          "addedColumn", ManagedPropertyType.integer,
          defaultValue: "2"));
      tableToKeep.removeColumn(tableToKeep.columnForName("columnToDelete"));
      tableToKeep
          .columnForName("columnToEdit")
          .defaultValue = "'foo'";

      schema.removeTable(schema.tableForName("tableToDelete"));

      schema.addTable(SchemaTable("foo", [
        SchemaColumn("foobar", ManagedPropertyType.integer, isIndexed: true)
      ]));

      expect(outSchema.differenceFrom(schema).hasDifferences, false);

      var insertResults = await store.execute(
          "INSERT INTO tableToKeep (columnToEdit) VALUES ('1') RETURNING columnToEdit, addedColumn");
      expect(insertResults, [
        ['1', 2]
      ]);
    });
  });

  group("Scanning for migration files", () {
    final temporaryDirectory = Directory("migration_tmp");
    final migrationsDirectory =
        Directory.fromUri(temporaryDirectory.uri.resolve("migrations"));
    final addFiles = (List<String> filenames) {
      filenames.forEach((name) {
        File.fromUri(migrationsDirectory.uri.resolve(name))
            .writeAsStringSync(" ");
      });
    };
    final addValidMigrationFile = (List<String> filenames) {
      filenames.forEach((name) {
        File.fromUri(migrationsDirectory.uri.resolve(name))
            .writeAsStringSync("""
class Migration1 extends Migration { @override Future upgrade() async {} @override Future downgrade() async {} @override Future seed() async {} }        
        """);
      });
    };

    setUp(() {
      temporaryDirectory.createSync();
      migrationsDirectory.createSync();
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    test("Ignores not .migration.dart files", () async {
      addValidMigrationFile(
          ["00000001.migration.dart", "a_foo.migration.dart"]);
      addFiles(["foobar.txt", ".DS_Store", "a.dart", "migration.dart"]);
      expect(migrationsDirectory.listSync().length, 6);

      var mock = MockMigratable(temporaryDirectory);
      var files = mock.projectMigrations;
      expect(files.length, 1);
      expect(files.first.uri.pathSegments.last, "00000001.migration.dart");
    });

    test("Migration files are ordered correctly", () async {
      addValidMigrationFile([
        "00000001.migration.dart",
        "2.migration.dart",
        "03_Foo.migration.dart",
        "10001_.migration.dart",
        "000001001.migration.dart"
      ]);
      expect(migrationsDirectory.listSync().length, 5);

      var mock = MockMigratable(temporaryDirectory);
      var files = mock.projectMigrations;
      expect(files.length, 5);
      expect(files[0].uri.pathSegments.last, "00000001.migration.dart");
      expect(files[1].uri.pathSegments.last, "2.migration.dart");
      expect(files[2].uri.pathSegments.last, "03_Foo.migration.dart");
      expect(files[3].uri.pathSegments.last, "000001001.migration.dart");
      expect(files[4].uri.pathSegments.last, "10001_.migration.dart");
    });
  });

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

class Migration1 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(SchemaTable("foo", [
      SchemaColumn("foobar", ManagedPropertyType.integer, isIndexed: true)
    ]));

    //database.renameTable(currentSchema["tableToRename"], "renamedTable");
    database.deleteTable("tableToDelete");

    database.addColumn(
        "tableToKeep",
        SchemaColumn("addedColumn", ManagedPropertyType.integer,
            defaultValue: "2"));
    database.deleteColumn("tableToKeep", "columnToDelete");
    //database.renameColumn()
    database.alterColumn("tableToKeep", "columnToEdit", (col) {
      col.defaultValue = "'foo'";
    });
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class MockMigratable extends CLICommand
    with CLIDatabaseManagingCommand, CLIProject {
  MockMigratable(this.projectDirectory) {
    migrationDirectory =
        Directory.fromUri(projectDirectory.uri.resolve("migrations"));
  }

  @override
  Directory migrationDirectory;

  @override
  Directory projectDirectory;

  @override
  Future<int> handle() async => 0;

  @override
  String get description => "";

  @override
  String get name => "";
}
