import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:io';
import 'cli_helpers.dart';
import 'generate_helpers.dart';

void main() {
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
      store = new PostgreSQLPersistentStore(
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

    test("Upgrade with no migration files returns 0 exit code", () async {
      var res = await runAqueductProcess(["db", "upgrade", "--connect", connectString], projectDirectory);
      expect(res.exitCode, 0);
      expect(res.output, contains("No migration files"));
    });

    test("Generate and execute initial schema makes workable DB", () async {
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      res = await runAqueductProcess(
          ["db", "upgrade", "--connect", connectString], projectDirectory);
      expect(res.exitCode, 0);

      var version = await store
          .execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1]
      ]);
      expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    });

    test("Database already up to date returns 0 status code, does not change version", () async {
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      res = await runAqueductProcess(
          ["db", "upgrade", "--connect", connectString], projectDirectory);
      expect(res.exitCode, 0);

      List<List<dynamic>> versionRow = await store
          .execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(versionRow.first.first, 1);
      var updateDate = versionRow.first.last;

      res = await runAqueductProcess(["db", "upgrade", "--connect", connectString], projectDirectory);
      expect(res.exitCode, 0);

      versionRow = await store
          .execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(versionRow.length, 1);
      expect(versionRow.first.last, equals(updateDate));
    });

    test("Multiple migration files are ran", () async {
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

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
          var res = await runAqueductProcess(["db", "generate"], projectDirectory);
          expect(res.exitCode, 0);

          res = await runAqueductProcess(
              ["db", "upgrade", "--connect", connectString], projectDirectory);
          expect(res.exitCode, 0);

          res = await runAqueductProcess(["db", "generate"], projectDirectory);
          expect(res.exitCode, 0);

          addLinesToUpgradeFile(
              new File.fromUri(migrationDirectory.uri
                  .resolve("00000002_Unnamed.migration.dart")),
              [
                "database.createTable(new SchemaTable(\"foo\", [new SchemaColumn.relationship(\"testobject\", ManagedPropertyType.bigInteger, relatedTableName: \"_testobject\", relatedColumnName: \"id\")]));",
                "database.deleteColumn(\"_testobject\", \"foo\");"
              ]);

          res = await runAqueductProcess(
              ["db", "upgrade", "--connect", connectString], projectDirectory);
          expect(res.exitCode, 0);

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