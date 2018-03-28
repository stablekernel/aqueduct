import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/executable.dart';
import 'dart:async';
import 'dart:io';
import 'cli_helpers.dart';

void main() {
  group("Cooperation", () {
    PersistentStore store;

    setUp(() {
      store = new PostgreSQLPersistentStore("dart", "dart", "localhost", 5432, "dart_test");
    });

    tearDown(() async {
      await store.close();
    });

    test("Migration subclasses can be executed and commands are generated and executed on the DB, schema is udpated",
        () async {
      // Note that the permutations of operations are covered in different tests, this is just to ensure that
      // executing a migration/upgrade all work together.
      var schema = new Schema([
        new SchemaTable("tableToKeep", [
          new SchemaColumn("columnToEdit", ManagedPropertyType.string),
          new SchemaColumn("columnToDelete", ManagedPropertyType.integer)
        ]),
        new SchemaTable("tableToDelete", [new SchemaColumn("whocares", ManagedPropertyType.integer)]),
        new SchemaTable("tableToRename", [new SchemaColumn("whocares", ManagedPropertyType.integer)])
      ]);

      var initialBuilder = new SchemaBuilder.toSchema(store, schema, isTemporary: true);
      for (var cmd in initialBuilder.commands) {
        await store.execute(cmd);
      }
      var db = new SchemaBuilder(store, schema, isTemporary: true);
      var mig = new Migration1()..database = db;

      await mig.upgrade();
      await store.upgrade(1, db.commands, temporary: true);

      // 'Sync up' that schema to compare it
      schema
          .tableForName("tableToKeep")
          .addColumn(new SchemaColumn("addedColumn", ManagedPropertyType.integer, defaultValue: "2"));
      schema.tableForName("tableToKeep").removeColumn(new SchemaColumn("columnToDelete", ManagedPropertyType.integer));
      schema.tableForName("tableToKeep").columnForName("columnToEdit").defaultValue = "'foo'";

      schema.removeTable(schema.tableForName("tableToDelete"));

      schema
          .addTable(new SchemaTable("foo", [new SchemaColumn("foobar", ManagedPropertyType.integer, isIndexed: true)]));

      expect(db.schema.differenceFrom(schema).hasDifferences, false);

      var insertResults = await db.store
          .execute("INSERT INTO tableToKeep (columnToEdit) VALUES ('1') RETURNING columnToEdit, addedColumn");
      expect(insertResults, [
        ['1', 2]
      ]);
    });
  });

  group("Scanning for migration files", () {
    var temporaryDirectory = new Directory("migration_tmp");
    var migrationsDirectory = new Directory.fromUri(temporaryDirectory.uri.resolve("migrations"));
    var addFiles = (List<String> filenames) {
      filenames.forEach((name) {
        new File.fromUri(migrationsDirectory.uri.resolve(name)).writeAsStringSync(" ");
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
      addFiles(["00000001.migration.dart", "foobar.txt", ".DS_Store", "a.dart", "migration.dart"]);
      expect(migrationsDirectory.listSync().length, 5);

      var mock = new MockMigratable(temporaryDirectory);
      var files = mock.migrationFiles;
      expect(files.length, 1);
      expect(files.first.uri.pathSegments.last, "00000001.migration.dart");
    });

    test("Migration files are ordered correctly", () async {
      addFiles([
        "00000001.migration.dart",
        "2.migration.dart",
        "03_Foo.migration.dart",
        "10001_.migration.dart",
        "000001001.migration.dart"
      ]);
      expect(migrationsDirectory.listSync().length, 5);

      var mock = new MockMigratable(temporaryDirectory);
      var files = mock.migrationFiles;
      expect(files.length, 5);
      expect(files[0].uri.pathSegments.last, "00000001.migration.dart");
      expect(files[1].uri.pathSegments.last, "2.migration.dart");
      expect(files[2].uri.pathSegments.last, "03_Foo.migration.dart");
      expect(files[3].uri.pathSegments.last, "000001001.migration.dart");
      expect(files[4].uri.pathSegments.last, "10001_.migration.dart");
    });

    test("Migration files with invalid form throw error", () async {
      addFiles(["a_foo.migration.dart"]);
      var mock = new MockMigratable(temporaryDirectory);
      try {
        mock.migrationFiles;
        expect(true, false);
      } on CLIException catch (e) {
        expect(e.message, contains("Migration files must have the following format"));
      }
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

    tearDown(() {
      Terminal.deleteTemporaryDirectory();
    });

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

      terminal.modifyFile("migrations/00000001_Initial.migration.dart", (contents) {
        final upgradeLocation = "upgrade()";
        final nextLine = contents.indexOf("\n", contents.indexOf(upgradeLocation));
        return contents.replaceRange(nextLine, nextLine + 1, """
        database.createTable(new SchemaTable(\"foo\", []));
        """);
      });

      res = await terminal.runAqueductCommand("db", ["validate"]);
      expect(res, isNot(0));
      expect(terminal.output, contains("Validation failed"));
    });

    test("Validating runs all migrations in directory and checks the total product", () async {
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      terminal.modifyFile("migrations/00000001_Initial.migration.dart", (contents) {
        final upgradeLocation = "upgrade()";
        final nextLine = contents.indexOf("\n", contents.indexOf(upgradeLocation));
        return contents.replaceRange(nextLine, nextLine + 1, """
        database.createTable(new SchemaTable(\"foo\", []));
        """);
      });

      res = await terminal.runAqueductCommand("db", ["validate"]);
      expect(res, isNot(0));
      expect(terminal.output, contains("Validation failed"));

      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      var secondMigrationFile =
          new File.fromUri(terminal.defaultMigrationDirectory.uri.resolve("00000002_Unnamed.migration.dart"));
      expect(secondMigrationFile.readAsStringSync(), contains("database.deleteTable(\"foo\")"));

      res = await terminal.runAqueductCommand("db", ["validate"]);
      expect(res, 0);
    });
  });
}

class Migration1 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(
        new SchemaTable("foo", [new SchemaColumn("foobar", ManagedPropertyType.integer, isIndexed: true)]));

    //database.renameTable(currentSchema["tableToRename"], "renamedTable");
    database.deleteTable("tableToDelete");

    database.addColumn("tableToKeep", new SchemaColumn("addedColumn", ManagedPropertyType.integer, defaultValue: "2"));
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

class MockMigratable extends CLIDatabaseManagingCommand {
  MockMigratable(this.projectDirectory) {
    migrationDirectory = new Directory.fromUri(projectDirectory.uri.resolve("migrations"));
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
