import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:io';

void main() {
  group("Versioning", () {
    PostgreSQLPersistentStore store;
    MigrationExecutor executor;

    setUp(() async {
      store = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
      executor = new MigrationExecutor(store, Directory.current.uri);
    });

    tearDown(() async {
      await store.execute("drop table _aqueduct_version_pgsql");
      await store.close();
    });

    test("When upgrading, version table is created if does not exist", () async {
      await executor.upgrade();

      var results = await executor.persistentStore.execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(results, []);
    });

    test("Version number is indicated by most recent dateOfUpgrade", () async {
      await executor.persistentStore.createVersionTableIfNecessary();
      await executor.persistentStore.execute("INSERT INTO _aqueduct_version_pgsql (versionNumber, dateOfUpgrade) VALUES (1, '2016-01-01 00:00:00')");
      await executor.persistentStore.execute("INSERT INTO _aqueduct_version_pgsql (versionNumber, dateOfUpgrade) VALUES (2, '2016-01-02 00:00:00')");
      var recentVersion = await executor.persistentStore.schemaVersion;
      expect(recentVersion, 2);
    });
  });

//  test("Migration subclasses can be executed and all commands are linked up", () async {
//    var schema = new Schema([
//      new SchemaTable("tableToKeep", [
//        new SchemaColumn("columnToEdit", PropertyType.integer),
//        new SchemaColumn("columnToDelete", PropertyType.integer)
//      ]),
//      new SchemaTable("tableToDelete", [
//        new SchemaColumn("whocares", PropertyType.integer)
//      ]),
//      new SchemaTable("tableToRename", [
//        new SchemaColumn("whocares", PropertyType.integer)
//      ])
//    ]);
//
//    var store = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
//    var db = new SchemaBuilder(store, schema, isTemporary: true);
//    var mig = new Migration1()
//      ..database = db;
//
//    await mig.upgrade();
//
//    //schema.tableForName("tableToKeep").columnForName("col1").isIndexed = true;
//    //schema.tables.add(Migration1.tableToAdd);
//
////    expect(db.schema.matches(schema), true);
//
//    print("${mig.database.commands}");
//  });
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

  Future downgrade() async {

  }

  Future seed() async {

  }
}