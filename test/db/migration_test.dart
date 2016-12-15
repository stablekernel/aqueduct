import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:io';

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
    var migrationDirectory = new Directory("migration_tmp");
    var addFiles = (List<String> filenames) {
      filenames.forEach((name) {
        new File.fromUri(migrationDirectory.uri.resolve(name))
            .writeAsStringSync(" ");
      });
    };
    MigrationExecutor executor;

    setUp(() {
      migrationDirectory.createSync();
      executor =
          new MigrationExecutor(null, null, null, migrationDirectory.uri);
    });

    tearDown(() {
      migrationDirectory.deleteSync(recursive: true);
    });

    test("Ignores not .migration.dart files", () {
      addFiles([
        "00000001.migration.dart",
        "foobar.txt",
        ".DS_Store",
        "a.dart",
        "migration.dart"
      ]);
      expect(migrationDirectory.listSync().length, 5);
      expect(executor.migrationFiles.map((f) => f.uri).toList(),
          [migrationDirectory.uri.resolve("00000001.migration.dart")]);
    });

    test("Migration files are ordered correctly", () {
      addFiles([
        "00000001.migration.dart",
        "2.migration.dart",
        "03_Foo.migration.dart",
        "10001_.migration.dart",
        "000001001.migration.dart"
      ]);
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
        expect(e.message,
            contains("Migration files must have the following format"));
      }
    });
  });

  group("Generating migration files", () {
    var projectDirectory = getTestProjectDirectory();
    var libraryName = "wildfire/wildfire.dart";
    var migrationDirectory =
        new Directory.fromUri(projectDirectory.uri.resolve("migrations"));
    var addFiles = (List<String> filenames) {
      filenames.forEach((name) {
        new File.fromUri(migrationDirectory.uri.resolve(name))
            .writeAsStringSync(" ");
      });
    };
    MigrationExecutor executor;

    setUp(() async {
      cleanTestProjectDirectory();
      executor = new MigrationExecutor(
          null, projectDirectory.uri, libraryName, migrationDirectory.uri);
    });

    tearDown(() {
      cleanTestProjectDirectory();
    });

    test("Ensure that running without getting dependencies throws error",
        () async {
      try {
        await executor.generate();
        expect(true, false);
      } on MigrationException catch (e) {
        expect(e.message, contains("Run pub get"));
      }
    });

    test("Ensure migration directory will get created on generation", () async {
      var res = await Process.runSync(
          "pub", ["get", "--no-packages-dir", "--offline"],
          workingDirectory: projectDirectory.path);
      print("${res.stdout} ${res.stderr}");

      expect(migrationDirectory.existsSync(), false);
      await executor.generate();
      expect(migrationDirectory.existsSync(), true);
    });

    test(
        "If there are no migration files, create an initial one that validates to schema",
        () async {
      await Process.runSync("pub", ["get", "--no-packages-dir", "--offline"],
          workingDirectory: projectDirectory.path);

      // Just to put something else in there that shouldn't flag it as an 'upgrade'
      migrationDirectory.createSync();

      addFiles(["notmigration.dart"]);
      await executor.generate();

      // Verify that this at least validates the schema.
      await executor.validate();
    });

    test("If there is already a migration file, create an upgrade file",
        () async {
      await Process.runSync("pub", ["get", "--no-packages-dir", "--offline"],
          workingDirectory: projectDirectory.path);

      await executor.generate();
      await executor.generate();
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

      await executor.validate();
    });
  });

  group("Validating", () {
    var projectDirectory = getTestProjectDirectory();
    var libraryName = "wildfire/wildfire.dart";
    var migrationDirectory =
        new Directory.fromUri(projectDirectory.uri.resolve("migrations"));
    MigrationExecutor executor;

    var expectedSchema = new Schema([
      new SchemaTable("_User", [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true),
        new SchemaColumn("email", ManagedPropertyType.string,
            isUnique: true),
        new SchemaColumn("username", ManagedPropertyType.string,
            isUnique: true, isIndexed: true),
        new SchemaColumn("hashedPassword", ManagedPropertyType.string),
        new SchemaColumn("salt", ManagedPropertyType.string)
      ]),
      new SchemaTable("_AuthCode", [
        new SchemaColumn("code", ManagedPropertyType.string, isPrimaryKey: true, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("issueDate", ManagedPropertyType.datetime, isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("expirationDate", ManagedPropertyType.datetime, isPrimaryKey: false, autoincrement: false, isIndexed: true, isNullable: false, isUnique: false),
        new SchemaColumn.relationship("resourceOwner", ManagedPropertyType.bigInteger, relatedTableName: "_User", relatedColumnName: "id", rule: ManagedRelationshipDeleteRule.cascade, isNullable: false, isUnique: false),
        new SchemaColumn.relationship("token", ManagedPropertyType.bigInteger, relatedTableName: "_authtoken", relatedColumnName: "id", rule: ManagedRelationshipDeleteRule.cascade, isNullable: true, isUnique: true),
        new SchemaColumn.relationship("client", ManagedPropertyType.string, relatedTableName: "_authclient", relatedColumnName: "id", rule: ManagedRelationshipDeleteRule.cascade, isNullable: false, isUnique: false),
      ]),
      new SchemaTable("_authToken", [
        new SchemaColumn("id", ManagedPropertyType.bigInteger, isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("accessToken", ManagedPropertyType.string, isPrimaryKey: false, autoincrement: false, isIndexed: true, isNullable: false, isUnique: true),
        new SchemaColumn("refreshToken", ManagedPropertyType.string, isPrimaryKey: false, autoincrement: false, isIndexed: true, isNullable: true, isUnique: true),
        new SchemaColumn("issueDate", ManagedPropertyType.datetime, isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("expirationDate", ManagedPropertyType.datetime, isPrimaryKey: false, autoincrement: false, isIndexed: true, isNullable: false, isUnique: false),
        new SchemaColumn.relationship("resourceOwner", ManagedPropertyType.bigInteger, relatedTableName: "_User", relatedColumnName: "id", rule: ManagedRelationshipDeleteRule.cascade, isNullable: false, isUnique: false),
        new SchemaColumn.relationship("client", ManagedPropertyType.string, relatedTableName: "_authclient", relatedColumnName: "id", rule: ManagedRelationshipDeleteRule.cascade, isNullable: false, isUnique: false),
      ]),
      new SchemaTable("_authclient", [
        new SchemaColumn("id", ManagedPropertyType.string, isPrimaryKey: true),
        new SchemaColumn("hashedSecret", ManagedPropertyType.string, isNullable: true),
        new SchemaColumn("salt", ManagedPropertyType.string, isNullable: true),
        new SchemaColumn("redirectURI", ManagedPropertyType.string, isUnique: true, isNullable: true),
      ]),
    ]);

    setUp(() async {
      cleanTestProjectDirectory();
      await Process.runSync("pub", ["get", "--no-packages-dir", "--offline"],
          workingDirectory: projectDirectory.path);
      executor = new MigrationExecutor(
          null, projectDirectory.uri, libraryName, migrationDirectory.uri);
    });

    tearDown(() {
      cleanTestProjectDirectory();
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
      await executor.generate();
      var outSchema = await executor.validate();

      var errors = <String>[];
      var ok = outSchema.matches(expectedSchema, errors);
      print("$errors");
      expect(ok, true);
      expect(errors, []);
    });

    test("Validating different schemas fails", () async {
      var file = await executor.generate();
      addLinesToUpgradeFile(
          file, ["database.createTable(new SchemaTable(\"foo\", []));"]);

      try {
        await executor.validate();
        expect(true, false);
      } on MigrationException catch (e) {
        expect(e.toString(), contains("Validation failed"));
        expect(e.toString(), contains("does not contain 'foo'"));
      }
    });

    test(
        "Validating runs all migrations in directory and checks the total product",
        () async {
      var firstFile = await executor.generate();
      addLinesToUpgradeFile(
          firstFile, ["database.createTable(new SchemaTable(\"foo\", []));"]);

      try {
        await executor.validate();
        expect(true, false);
      } on MigrationException catch (e) {
        expect(e.toString(), contains("Validation failed"));
        expect(e.toString(), contains("does not contain 'foo'"));
      }

      var nextGenFile = await executor.generate();
      addLinesToUpgradeFile(nextGenFile, ["database.deleteTable(\"foo\");"]);

      var outSchema = await executor.validate();
      expect(outSchema.matches(expectedSchema), true);
    });
  });

  group("Execution", () {
    var projectDirectory = getTestProjectDirectory();
    var libraryName = "wildfire/wildfire.dart";
    var migrationDirectory =
        new Directory.fromUri(projectDirectory.uri.resolve("migrations"));
    MigrationExecutor executor;

    setUp(() async {
      cleanTestProjectDirectory();
      await Process.runSync("pub", ["get", "--no-packages-dir", "--offline"],
          workingDirectory: projectDirectory.path);
      var store = new PostgreSQLPersistentStore.fromConnectionInfo(
          "dart", "dart", "localhost", 5432, "dart_test");
      executor = new MigrationExecutor(
          store, projectDirectory.uri, libraryName, migrationDirectory.uri);
    });

    tearDown(() async {
      cleanTestProjectDirectory();
      var tables = [
        "_aqueduct_version_pgsql", "foo", "_authcode",
        "_authtoken", "_user", "_authclient"];
      await Future.wait(tables.map((t) {
        return executor.persistentStore.execute("DROP TABLE IF EXISTS $t");
      }));
    });

    test("Generate and execute initial schema makes workable DB", () async {
      await executor.generate();
      await executor.upgrade();

      var version = await executor.persistentStore
          .execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [[1]]);
      expect(await columnsOfTable(executor, "_user"),
          ["email", "id", "username", "hashedpassword", "salt"]);
      expect(await columnsOfTable(executor, "_authtoken"),
          ["id", "accesstoken", "refreshtoken", "issuedate",
          "expirationdate", "resourceowner_id", "client_id"]);
    });

    test("Multiple migration files are ran", () async {
      await executor.generate();

      File nextGen = await executor.generate();
      addLinesToUpgradeFile(nextGen, [
        "database.createTable(new SchemaTable(\"foo\", [new SchemaColumn.relationship(\"user\", ManagedPropertyType.bigInteger, relatedTableName: \"_user\", relatedColumnName: \"id\")]));",
        "database.deleteColumn(\"_user\", \"username\");"
      ]);
      await executor.upgrade();

      var version = await executor.persistentStore
          .execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [[1], [2]]);
      expect(await columnsOfTable(executor, "_user"),
          ["email", "id", "hashedpassword", "salt"]);
      expect(await columnsOfTable(executor, "foo"), ["user_id"]);
    });

    test("Only later migration files are ran if already at a version",
        () async {
      await executor.generate();
      await executor.upgrade();

      File nextGen = await executor.generate();
      addLinesToUpgradeFile(nextGen, [
        "database.createTable(new SchemaTable(\"foo\", [new SchemaColumn.relationship(\"user\", ManagedPropertyType.bigInteger, relatedTableName: \"_user\", relatedColumnName: \"id\")]));",
        "database.deleteColumn(\"_user\", \"username\");"
      ]);

      await executor.upgrade();

      expect(await columnsOfTable(executor, "_user"),
          ["email", "id", "hashedpassword", "salt"]);
      expect(await columnsOfTable(executor, "foo"), ["user_id"]);
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

Directory getTestProjectDirectory() {
  return new Directory.fromUri(
      Directory.current.uri.resolve("test/test_project"));
}

void cleanTestProjectDirectory() {
  var dir = getTestProjectDirectory();

  var packagesFile = new File.fromUri(dir.uri.resolve(".packages"));
  var pubDir = new Directory.fromUri(dir.uri.resolve(".pub"));
  var packagesDir = new Directory.fromUri(dir.uri.resolve("packages"));
  var migrationsDir = new Directory.fromUri(dir.uri.resolve("migrations"));
  var lockFile = new File.fromUri(dir.uri.resolve("pubspec.lock"));
  [packagesFile, pubDir, packagesDir, migrationsDir, lockFile].forEach((f) {
    if (f.existsSync()) {
      f.deleteSync(recursive: true);
    }
  });
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

Future<List<String>> columnsOfTable(MigrationExecutor executor, String tableName) async {
  List<List<String>> results = await executor.persistentStore.execute("select column_name from information_schema.columns where "
      "table_name='$tableName'");
  return results.map((rows) => rows.first).toList();
}
