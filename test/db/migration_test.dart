import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';

void main() {
  test("Migration subclasses can be executed and all commands are linked up", () async {
    var schema = new Schema.withTables([
      new SchemaTable.withColumns("tableToKeep", [
        new SchemaColumn.withName("columnToEdit", PropertyType.integer),
        new SchemaColumn.withName("columnToDelete", PropertyType.integer)
      ]),
      new SchemaTable.withColumns("tableToDelete", [
        new SchemaColumn.withName("whocares", PropertyType.integer)
      ]),
      new SchemaTable.withColumns("tableToRename", [
        new SchemaColumn.withName("whocares", PropertyType.integer)
      ])
    ]);

    var store = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
    var db = new SchemaBuilder(store, schema, isTemporary: true);
    var mig = new Migration1()
      ..database = db;

    await mig.upgrade();

    schema.tables.first.columnForName("col1").isIndexed = true;
    schema.tables.add(Migration1.tableToAdd);

    expect(db.schema.matches(schema), true);

    print("${mig.database.commands}");
  });
}

class Migration1 extends Migration {
  static SchemaTable tableToAdd = new SchemaTable.withColumns("addedTable", [
    new SchemaColumn.withName("col", PropertyType.integer)
  ]);
/*
List<String> createTable(SchemaTable table, {bool isTemporary: false});
  List<String> renameTable(SchemaTable table, String name);
  List<String> deleteTable(SchemaTable table);

  List<String> addColumn(SchemaTable table, SchemaColumn column);
  List<String> deleteColumn(SchemaTable table, SchemaColumn column);
  List<String> renameColumn(SchemaTable table, SchemaColumn column, String name);
  List<String> alterColumn(SchemaTable table, SchemaColumn existingColumn, SchemaColumn targetColumn, {String unencodedInitialValue});

 */

  Future upgrade() async {
    database.createTable(tableToAdd);
    //database.renameTable(currentSchema["tableToRename"], "renamedTable");
    database.deleteTable("tableToDelete");

    database.addColumn("tableToKeep", new SchemaColumn.withName("addedColumn", PropertyType.integer));
    database.deleteColumn("tableToKeep", "columnToDelete");
    //database.renameColumn()
    database.alterColumn(currentSchema["tableToKeep"], "columnToEdit", (col) {
      col.defaultValue = "'foo'";
    });
  }

  Future downgrade() async {

  }

  Future seed() async {

  }
}