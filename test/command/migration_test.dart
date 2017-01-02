import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/executable.dart';
import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import '../helpers.dart';

void main() {
  group("Cooperation", () {
    PersistentStore store;

    setUp(() {
      store = new PostgreSQLPersistentStore.fromConnectionInfo(
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
      var schema = new Schema([
        new SchemaTable("tableToKeep", [
          new SchemaColumn("columnToEdit", ManagedPropertyType.string),
          new SchemaColumn("columnToDelete", ManagedPropertyType.integer)
        ]),
        new SchemaTable("tableToDelete",
            [new SchemaColumn("whocares", ManagedPropertyType.integer)]),
        new SchemaTable("tableToRename",
            [new SchemaColumn("whocares", ManagedPropertyType.integer)])
      ]);

      var initialBuilder =
          new SchemaBuilder.toSchema(store, schema, isTemporary: true);
      for (var cmd in initialBuilder.commands) {
        await store.execute(cmd);
      }
      var db = new SchemaBuilder(store, schema, isTemporary: true);
      var mig = new Migration1()..database = db;

      await mig.upgrade();
      await store.upgrade(1, db.commands, temporary: true);

      // 'Sync up' that schema to compare it
      schema.tableForName("tableToKeep").addColumn(new SchemaColumn(
          "addedColumn", ManagedPropertyType.integer,
          defaultValue: "2"));
      schema.tableForName("tableToKeep").removeColumn(
          new SchemaColumn("columnToDelete", ManagedPropertyType.integer));
      schema
          .tableForName("tableToKeep")
          .columnForName("columnToEdit")
          .defaultValue = "'foo'";

      schema.removeTable(schema.tableForName("tableToDelete"));

      schema.tables.add(new SchemaTable("foo", [
        new SchemaColumn("foobar", ManagedPropertyType.integer, isIndexed: true)
      ]));

      expect(db.schema.matches(schema), true);

      var insertResults = await db.store.execute(
          "INSERT INTO tableToKeep (columnToEdit) VALUES ('1') RETURNING columnToEdit, addedColumn");
      expect(insertResults, [
        ['1', 2]
      ]);
    });
  });

  group("Scanning for migration files", () {
    var temporaryDirectory = new Directory("migration_tmp");
    var migrationsDirectory =
        new Directory.fromUri(temporaryDirectory.uri.resolve("migrations"));
    var addFiles = (List<String> filenames) {
      filenames.forEach((name) {
        new File.fromUri(migrationsDirectory.uri.resolve(name))
            .writeAsStringSync(" ");
      });
    };

    PersistentStore store;

    setUp(() {
      temporaryDirectory.createSync();
      migrationsDirectory.createSync();
      store = new PostgreSQLPersistentStore.fromConnectionInfo(
          "dart", "dart", "localhost", 5432, "dart_test");
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    test("Ignores not .migration.dart files", () async {
      addFiles([
        "00000001.migration.dart",
        "foobar.txt",
        ".DS_Store",
        "a.dart",
        "migration.dart"
      ]);
      expect(migrationsDirectory.listSync().length, 5);

      var mock = new MockMigratable(temporaryDirectory);
      var files = await mock.migrationFiles;
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
      var files = await mock.migrationFiles;
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
        await mock.migrationFiles;
        expect(true, false);
      } on CLIException catch (e) {
        expect(e.message,
            contains("Migration files must have the following format"));
      }
    });
  });

  group("Generating migration files", () {
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

  group("Validating", () {
    var projectSourceDirectory = getTestProjectDirectory("initial");
    Directory projectDirectory = new Directory("test_project");
    var migrationDirectory =
        new Directory.fromUri(projectDirectory.uri.resolve("migrations"));

    setUp(() async {
      createTestProject(projectSourceDirectory, projectDirectory);
      await runPubGet(projectDirectory, offline: true);
    });

    tearDown(() {
      projectDirectory.deleteSync(recursive: true);
    });

    test("If validating with no migration dir, get error", () async {
      expect(
          await runAqueductProcess(["db", "validate"], projectDirectory) != 0,
          true);
    });

    test("Validating two equal schemas succeeds", () async {
      await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(await runAqueductProcess(["db", "validate"], projectDirectory), 0);
    });

    test("Validating different schemas fails", () async {
      await runAqueductProcess(["db", "generate"], projectDirectory);
      addLinesToUpgradeFile(
          new File.fromUri(migrationDirectory.uri
              .resolve("00000001_Initial.migration.dart")),
          ["database.createTable(new SchemaTable(\"foo\", []));"]);

      expect(
          await runAqueductProcess(["db", "validate"], projectDirectory) != 0,
          true);
    });

    test(
        "Validating runs all migrations in directory and checks the total product",
        () async {
      await runAqueductProcess(["db", "generate"], projectDirectory);
      addLinesToUpgradeFile(
          new File.fromUri(migrationDirectory.uri
              .resolve("00000001_Initial.migration.dart")),
          ["database.createTable(new SchemaTable(\"foo\", []));"]);

      expect(
          await runAqueductProcess(["db", "validate"], projectDirectory) != 0,
          true);

      await runAqueductProcess(["db", "generate"], projectDirectory);
      addLinesToUpgradeFile(
          new File.fromUri(migrationDirectory.uri
              .resolve("00000002_Unnamed.migration.dart")),
          ["database.deleteTable(\"foo\");"]);

      expect(await runAqueductProcess(["db", "validate"], projectDirectory), 0);
    });
  });

  group("Execution", () {
    var projectSourceDirectory = getTestProjectDirectory("initial");
    Directory projectDirectory = new Directory("test_project");
    var migrationDirectory =
        new Directory.fromUri(projectDirectory.uri.resolve("migrations"));
    var connectInfo = new DatabaseConnectionConfiguration.withConnectionInfo(
        "dart", "dart", "localhost", 5432, "dart_test");
    var connectString =
        "postgres://${connectInfo.username}:${connectInfo.password}@${connectInfo.host}:${connectInfo.port}/${connectInfo.databaseName}";
    PostgreSQLPersistentStore store;

    setUp(() async {
      store = new PostgreSQLPersistentStore.fromConnectionInfo(
          connectInfo.username,
          connectInfo.password,
          connectInfo.host,
          connectInfo.port,
          connectInfo.databaseName);
      createTestProject(projectSourceDirectory, projectDirectory);
      await runPubGet(projectDirectory, offline: true);
    });

    tearDown(() {
      projectDirectory.deleteSync(recursive: true);
    });

    tearDown(() async {
      var tables = [
        "_aqueduct_version_pgsql",
        "foo",
        "_testobject",
      ];

      await Future.wait(tables.map((t) {
        return store.execute("DROP TABLE IF EXISTS $t");
      }));
      await store?.close();
    });

    test("Generate and execute initial schema makes workable DB", () async {
      await runAqueductProcess(["db", "generate"], projectDirectory);
      await runAqueductProcess(
          ["db", "upgrade", "--connect", connectString], projectDirectory);

      var version = await store
          .execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1]
      ]);
      expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    });

    test("Multiple migration files are ran", () async {
      await runAqueductProcess(["db", "generate"], projectDirectory);
      await runAqueductProcess(["db", "generate"], projectDirectory);

      addLinesToUpgradeFile(
          new File.fromUri(migrationDirectory.uri
              .resolve("00000002_Unnamed.migration.dart")),
          [
            "database.createTable(new SchemaTable(\"foo\", [new SchemaColumn.relationship(\"testobject\", ManagedPropertyType.bigInteger, relatedTableName: \"_testobject\", relatedColumnName: \"id\")]));",
            "database.deleteColumn(\"_testobject\", \"foo\");"
          ]);

      await runAqueductProcess(
          ["db", "upgrade", "--connect", connectString], projectDirectory);

      var version = await store
          .execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1],
        [2]
      ]);
      expect(await columnsOfTable(store, "_testobject"), ["id"]);
      expect(await columnsOfTable(store, "foo"), ["testobject_id"]);
    });

    test("Only later migration files are ran if already at a version",
        () async {
      await runAqueductProcess(["db", "generate"], projectDirectory);
      await runAqueductProcess(
          ["db", "upgrade", "--connect", connectString], projectDirectory);

      await runAqueductProcess(["db", "generate"], projectDirectory);
      addLinesToUpgradeFile(
          new File.fromUri(migrationDirectory.uri
              .resolve("00000002_Unnamed.migration.dart")),
          [
            "database.createTable(new SchemaTable(\"foo\", [new SchemaColumn.relationship(\"testobject\", ManagedPropertyType.bigInteger, relatedTableName: \"_testobject\", relatedColumnName: \"id\")]));",
            "database.deleteColumn(\"_testobject\", \"foo\");"
          ]);
      ;

      await runAqueductProcess(
          ["db", "upgrade", "--connect", connectString], projectDirectory);

      var version = await store
          .execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1],
        [2]
      ]);
      expect(await columnsOfTable(store, "_testobject"), ["id"]);
      expect(await columnsOfTable(store, "foo"), ["testobject_id"]);
    });
  });
}

class Migration1 extends Migration {
  Future upgrade() async {
    database.createTable(new SchemaTable("foo", [
      new SchemaColumn("foobar", ManagedPropertyType.integer, isIndexed: true)
    ]));

    //database.renameTable(currentSchema["tableToRename"], "renamedTable");
    database.deleteTable("tableToDelete");

    database.addColumn(
        "tableToKeep",
        new SchemaColumn("addedColumn", ManagedPropertyType.integer,
            defaultValue: "2"));
    database.deleteColumn("tableToKeep", "columnToDelete");
    //database.renameColumn()
    database.alterColumn("tableToKeep", "columnToEdit", (col) {
      col.defaultValue = "'foo'";
    });
  }

  Future downgrade() async {}
  Future seed() async {}
}

Directory getTestProjectDirectory(String name) {
  return new Directory.fromUri(Directory.current.uri
      .resolve("test/command/migration_test_projects/$name"));
}

void addLinesToUpgradeFile(File upgradeFile, List<String> extraLines) {
  var lines = upgradeFile
      .readAsStringSync()
      .split("\n")
      .map((line) {
        if (line.contains("Future upgrade()")) {
          var l = [line];
          l.addAll(extraLines);
          return l;
        }
        return [line];
      })
      .expand((lines) => lines)
      .join("\n");

  upgradeFile.writeAsStringSync(lines);
}

Future<List<String>> columnsOfTable(
    PersistentStore persistentStore, String tableName) async {
  List<List<String>> results = await persistentStore
      .execute("select column_name from information_schema.columns where "
          "table_name='$tableName'");
  return results.map((rows) => rows.first).toList();
}

Future<int> runAqueductProcess(
    List<String> commands, Directory workingDirectory) async {
  commands.add("--directory");
  commands.add("${workingDirectory.path}");

  var cmd = new Runner();
  var results = cmd.options.parse(commands);

  return cmd.process(results);
}

class MockMigratable extends CLIDatabaseMigratable {
  MockMigratable(this.projectDirectory);
  Directory projectDirectory;
  ArgResults values;
}
