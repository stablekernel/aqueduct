import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';
import 'dart:async';
import 'cli_helpers.dart';

String getAbsoluteDir(String relative) {
  final current = Directory.current;
  return current.uri.resolve("test/").resolve("db/").resolve("postgresql/").resolve("migration/").resolve(relative).path;
}

void main() {
  group("Execution", () {
    Terminal terminal;
    var connectInfo =
        new DatabaseConnectionConfiguration.withConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
    var connectString = "postgres://${connectInfo.username}:${connectInfo.password}@${connectInfo.host}:${connectInfo
        .port}/${connectInfo.databaseName}";
    PostgreSQLPersistentStore store;

    setUp(() async {
      store = new PostgreSQLPersistentStore(
          connectInfo.username, connectInfo.password, connectInfo.host, connectInfo.port, connectInfo.databaseName);
      terminal = await Terminal.createProject();
      await terminal.getDependencies(offline: true);
    });

    tearDown(() async {
      var tables = [
        "_aqueduct_version_pgsql",
        "_foo",
        "_testobject",
      ];

      await Future.wait(tables.map((t) {
        return store.execute("DROP TABLE IF EXISTS $t");
      }));
      await store?.close();

      Terminal.deleteTemporaryDirectory();
    });

    test("Upgrade with no migration files returns 0 exit code", () async {
      final dir = getAbsoluteDir("case0/");
      var res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, 0);
      expect(terminal.output, contains("No migration files"));
    });

    test("Generate and execute initial schema makes workable DB", () async {
      final dir = getAbsoluteDir("case1/");
      final res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, 0);

      var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1]
      ]);
      expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    });

    test("Database already up to date returns 0 status code, does not change version", () async {
      final dir = getAbsoluteDir("case2/");
      var res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, 0);

      List<List<dynamic>> versionRow =
          await store.execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(versionRow.first.first, 1);
      var updateDate = versionRow.first.last;

      terminal.clearOutput();
      res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, 0);

      versionRow = await store.execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(versionRow.length, 1);
      expect(versionRow.first.last, equals(updateDate));
      expect(terminal.output, contains("already current (version: 1)"));
    });

    test("Multiple migration files are ran", () async {
      final dir = getAbsoluteDir("case3/");
      var res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, 0);

      var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1],
        [2]
      ]);
      expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
      expect(await columnsOfTable(store, "_foo"), ["id", "testobject_id"]);
    });

    test("Only later migration files are ran if already at a version", () async {
      var dir = getAbsoluteDir("case4-1/");
      var res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, 0);

      var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1]
      ]);

      expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
      expect(await columnsOfTable(store, "_foo"), []);

      dir = getAbsoluteDir("case4-2/");
      res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, 0);

      version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1],
        [2]
      ]);

      expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
      expect(await columnsOfTable(store, "_foo"), ["id", "testobject_id"]);
    });

    test("If migration throws exception, rollback any changes", () async {
      var dir = getAbsoluteDir("case5/");
      var res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, isNot(0));

      try {
        await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
        fail('unreachable');
      } on PostgreSQLException catch (e) {
        expect(e.toString(), contains("relation \"_aqueduct_version_pgsql\" does not exist"));
      }
      expect(await columnsOfTable(store, "_testobject"), []);
    });

    test("If migration fails and more migrations are pending, the pending migrations are cancelled", () async {
      var dir = getAbsoluteDir("case6/");
      var res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, isNot(0));
      expect(terminal.output, contains("Applied version 1 successfully"));
      expect(terminal.output, contains("relation \"_unknowntable\" does not exist"));

      var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1]
      ]);

      expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
      expect(await columnsOfTable(store, "_foo"), []);
    });

    test("If seed fails, all schema changes are rolled back", () async {
      var dir = getAbsoluteDir("case7/");
      var res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString, "--migration-directory", dir]);
      expect(res, isNot(0));

      try {
        await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
        fail('unreachable');
      } on PostgreSQLException catch (e) {
        expect(e.toString(), contains("relation \"_aqueduct_version_pgsql\" does not exist"));
      }
      expect(await columnsOfTable(store, "_testobject"), []);
    });
  });
}

Future<List<String>> columnsOfTable(PersistentStore persistentStore, String tableName) async {
  List<List<String>> results = await persistentStore.execute("select column_name from information_schema.columns where "
      "table_name='$tableName'");
  return results.map((rows) => rows.first).toList();
}
