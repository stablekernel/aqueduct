import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:io';

void main() {
  group("Cooperation", () {
    PersistentStore store;
    setUp(() {
      store = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
    });

    tearDown(() async {
      await store.close();
    });

    test("Migration subclasses can be executed and commands are generated and executed on the DB, schema is udpated", () async {
      // Note that the permutations of operations are covered in different tests, this is just to ensure that
      // executing a migration/upgrade all work together.
      var schema = new Schema([
        new SchemaTable("tableToKeep", [
          new SchemaColumn("columnToEdit", PropertyType.string),
          new SchemaColumn("columnToDelete", PropertyType.integer)
        ]),
        new SchemaTable("tableToDelete", [
          new SchemaColumn("whocares", PropertyType.integer)
        ]),
        new SchemaTable("tableToRename", [
          new SchemaColumn("whocares", PropertyType.integer)
        ])
      ]);

      var initialBuilder = new SchemaBuilder.toSchema(store, schema, isTemporary: true);
      for (var cmd in initialBuilder.commands) {
        await store.execute(cmd);
      }
      var db = new SchemaBuilder(store, schema, isTemporary: true);
      var mig = new Migration1()
        ..database = db;

      await mig.upgrade();
      await store.upgrade(1, db.commands, temporary: true);

      // 'Sync up' that schema to compare it
      schema.tableForName("tableToKeep").addColumn(new SchemaColumn("addedColumn", PropertyType.integer, defaultValue: "2"));
      schema.tableForName("tableToKeep").removeColumn(new SchemaColumn("columnToDelete", PropertyType.integer));
      schema.tableForName("tableToKeep").columnForName("columnToEdit").defaultValue = "'foo'";

      schema.removeTable(schema.tableForName("tableToDelete"));

      schema.tables.add(new SchemaTable("foo", [
        new SchemaColumn("foobar", PropertyType.integer, isIndexed: true)
      ]));

      expect(db.schema.matches(schema), true);

      var insertResults = await db.store.execute("INSERT INTO tableToKeep (columnToEdit) VALUES ('1') RETURNING columnToEdit, addedColumn");
      expect(insertResults, [['1', 2]]);
    });
  });

  group("Scanning for migration files", () {
    var migrationDirectory = new Directory("migration_tmp");
    var addFiles = (List<String> filenames) {
      filenames.forEach((name) {
        new File.fromUri(migrationDirectory.uri.resolve(name)).writeAsStringSync(" ");
      });
    };
    MigrationExecutor executor;

    setUp(() {
      migrationDirectory.createSync();
      executor = new MigrationExecutor(null, null, null, migrationDirectory.uri);
    });

    tearDown(() {
      migrationDirectory.deleteSync(recursive: true);
    });

    test("Ignores not .migration.dart files", () {
      addFiles(["00000001.migration.dart", "foobar.txt", ".DS_Store", "a.dart", "migration.dart"]);
      expect(migrationDirectory.listSync().length, 5);
      expect(executor.migrationFiles.map((f) => f.uri).toList(), [
        migrationDirectory.uri.resolve("00000001.migration.dart")
      ]);
    });

    test("Migration files are ordered correctly", () {
      addFiles(["00000001.migration.dart", "2.migration.dart", "03_Foo.migration.dart", "10001_.migration.dart", "000001001.migration.dart"]);
      expect(executor.migrationFiles.map((f) => f.uri).toList(), [
        migrationDirectory.uri.resolve("00000001.migration.dart"),
        migrationDirectory.uri.resolve("2.migration.dart"),
        migrationDirectory.uri.resolve("03_Foo.migration.dart"),
        migrationDirectory.uri.resolve("000001001.migration.dart"),
        migrationDirectory.uri.resolve("10001_.migration.dart")
      ]);
    });

    test("Migration files with invalid form throw error", () {
      addFiles(["a_foo.migration.dart"]);
      try {
        executor.migrationFiles;
        expect(true, false);
      } on MigrationException catch (e) {
        expect(e.message, contains("Migration files must have the following format"));
      }
    });
  });

  group("Generating migration files", () {
    var projectDirectory = getTestProjectDirectory();
    var libraryName = "wildfire/wildfire.dart";
    var migrationDirectory = new Directory.fromUri(projectDirectory.uri.resolve("migrations"));
    var addFiles = (List<String> filenames) {
      filenames.forEach((name) {
        new File.fromUri(migrationDirectory.uri.resolve(name)).writeAsStringSync(" ");
      });
    };
    MigrationExecutor executor;

    setUp(() async {
      cleanTestProjectDirectory();
      executor = new MigrationExecutor(null, projectDirectory.uri, libraryName, migrationDirectory.uri);
    });

    tearDown(() {
      cleanTestProjectDirectory();
    });

    test("Ensure that running without getting dependencies throws error", () async {
      try {
        await executor.generate();
      } on MigrationException catch (e) {
        expect(e.message, contains("Run pub get"));
      }
    });

    test("Ensure migration directory will get created on generation", () async {
      await Process.runSync("pub", ["get", "--no-packages-dir"], workingDirectory: projectDirectory.path);

      expect(migrationDirectory.existsSync(), false);
      await executor.generate();
      expect(migrationDirectory.existsSync(), true);
    });

    test("If there are no migration files, create an initial one that validates to schema", () async {
      await Process.runSync("pub", ["get", "--no-packages-dir"], workingDirectory: projectDirectory.path);

      // Just to put something else in there that shouldn't flag it as an 'upgrade'
      migrationDirectory.createSync();
      addFiles(["notmigration.dart"]);
      await executor.generate();

      // Verify that this at least validates the schema.
      await executor.validate();
    });

    test("If there is already a migration file, create an upgrade file", () async {
      await Process.runSync("pub", ["get", "--no-packages-dir"], workingDirectory: projectDirectory.path);

      await executor.generate();
      await executor.generate();
      expect(migrationDirectory.listSync().where((fse) => !fse.uri.pathSegments.last.startsWith(".")), hasLength(2));
      expect(new File.fromUri(migrationDirectory.uri.resolve("00000001_Initial.migration.dart")).existsSync(), true);
      expect(new File.fromUri(migrationDirectory.uri.resolve("00000002_Unnamed.migration.dart")).existsSync(), true);
    });

    test("If validating with no migration dir, get error", () async {
      try {
        await executor.validate();
        expect(true, false);
      } on MigrationException catch (e) {
        expect(e.message, contains("nothing to validate"));
      }
    });

    test("Validating two equal schemas succeeds", () async {
      await Process.runSync("pub", ["get", "--no-packages-dir"], workingDirectory: projectDirectory.path);

      await executor.generate();
      await executor.validate();
    });

    test("Validating different schemas fails", () async {
    });

    test("Validating runs all migrations in directory", () async {

    });
  });
}

class Migration1 extends Migration {
  Future upgrade() async {
    database.createTable(new SchemaTable("foo", [
      new SchemaColumn("foobar", PropertyType.integer, isIndexed: true)
    ]));

    //database.renameTable(currentSchema["tableToRename"], "renamedTable");
    database.deleteTable("tableToDelete");

    database.addColumn("tableToKeep", new SchemaColumn("addedColumn", PropertyType.integer, defaultValue: "2"));
    database.deleteColumn("tableToKeep", "columnToDelete");
    //database.renameColumn()
    database.alterColumn("tableToKeep", "columnToEdit", (col) {
      col.defaultValue = "'foo'";
    });
  }
  Future downgrade() async {}
  Future seed() async {}
}

Directory getTestProjectDirectory() {
  return new Directory.fromUri(Directory.current.uri.resolve("test/test_project"));
}

void cleanTestProjectDirectory() {
  var dir = getTestProjectDirectory();

  var packagesFile = new File.fromUri(dir.uri.resolve(".packages"));
  var pubDir = new Directory.fromUri(dir.uri.resolve(".pub"));
  var packagesDir = new Directory.fromUri(dir.uri.resolve("packages"));
  var migrationsDir = new Directory.fromUri(dir.uri.resolve("migrations"));
  [packagesFile, pubDir, packagesDir, migrationsDir].forEach((f) {
    if (f.existsSync()) {
      f.deleteSync(recursive: true);
    }
  });
}