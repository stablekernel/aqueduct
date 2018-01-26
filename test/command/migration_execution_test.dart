import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'cli_helpers.dart';

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
      terminal.addOrReplaceFile("lib/application_test.dart", """
class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int id;

  String foo;
}      
      """);
    });

    tearDown(() {
      Terminal.deleteTemporaryDirectory();
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
      var res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString]);
      expect(res, 0);
      expect(terminal.output, contains("No migration files"));
    });

    test("Generate and execute initial schema makes workable DB", () async {
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString]);
      expect(res, 0);

      var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1]
      ]);
      expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    });

    test("Database already up to date returns 0 status code, does not change version", () async {
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString]);
      expect(res, 0);

      List<List<dynamic>> versionRow =
          await store.execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(versionRow.first.first, 1);
      var updateDate = versionRow.first.last;

      res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString]);
      expect(res, 0);

      versionRow = await store.execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(versionRow.length, 1);
      expect(versionRow.first.last, equals(updateDate));
    });

    test("Multiple migration files are ran", () async {
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      terminal.modifyFile("migrations/00000002_Unnamed.migration.dart", (contents) {
        final upgradeLocation = "upgrade()";
        final nextLine = contents.indexOf("\n", contents.indexOf(upgradeLocation));
        return contents.replaceRange(nextLine, nextLine + 1, """
        database.createTable(new SchemaTable(\"foo\", [new SchemaColumn.relationship(\"testobject\", ManagedPropertyType.bigInteger, relatedTableName: \"_testobject\", relatedColumnName: \"id\")]));
        database.deleteColumn(\"_testobject\", \"foo\");
        """);
      });
      await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString]);

      var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1],
        [2]
      ]);
      expect(await columnsOfTable(store, "_testobject"), ["id"]);
      expect(await columnsOfTable(store, "foo"), ["testobject_id"]);
    });

    test("Only later migration files are ran if already at a version", () async {
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString]);
      expect(res, 0);

      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);

      terminal.modifyFile("migrations/00000002_Unnamed.migration.dart", (contents) {
        final upgradeLocation = "upgrade()";
        final nextLine = contents.indexOf("\n", contents.indexOf(upgradeLocation));
        return contents.replaceRange(nextLine, nextLine + 1, """
        database.createTable(new SchemaTable(\"foo\", [new SchemaColumn.relationship(\"testobject\", ManagedPropertyType.bigInteger, relatedTableName: \"_testobject\", relatedColumnName: \"id\")]));
        database.deleteColumn(\"_testobject\", \"foo\");
        """);
      });

      res = await terminal.runAqueductCommand("db", ["upgrade", "--connect", connectString]);
      expect(res, 0);

      var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
      expect(version, [
        [1],
        [2]
      ]);
      expect(await columnsOfTable(store, "_testobject"), ["id"]);
      expect(await columnsOfTable(store, "foo"), ["testobject_id"]);
    });
  });
}

Future<List<String>> columnsOfTable(PersistentStore persistentStore, String tableName) async {
  List<List<String>> results = await persistentStore.execute("select column_name from information_schema.columns where "
      "table_name='$tableName'");
  return results.map((rows) => rows.first).toList();
}
