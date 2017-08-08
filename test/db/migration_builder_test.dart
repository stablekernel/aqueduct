import 'dart:async';
import 'dart:isolate';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Create table", () async {
    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'"),
      new SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz", relatedTableName: "abc", rule: ManagedRelationshipDeleteRule.cascade)
    ]);

    var commands = [
      MigrationBuilder.createTableString(expectedTable, "")
    ];
    var source = sourceForSchemaUpgrade(new Schema.empty(), commands);
    var response = await runSource(source, new Schema([]));

    var schema = new Schema.fromMap(response);

    expect(schema.tables.length, 1);
    expect(expectedTable.differenceFrom(schema.tables.first).hasDifferences, false);
  });

  test("Delete table", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'"),
      new SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz", relatedTableName: "abc", rule: ManagedRelationshipDeleteRule.cascade)
    ]);
    var existingSchema = new Schema([
      existingTable,
      new SchemaTable("verify", [])
    ]);

    var commands = [
      MigrationBuilder.deleteTableString("foo", "")
    ];

    var source = sourceForSchemaUpgrade(existingSchema, commands);
    var response = await runSource(source, existingSchema);
    var schema = new Schema.fromMap(response);
    expect(schema.tables.length, 1);
    expect(schema.tables.first.name, "verify");
  });

  test("Add column", () async {
    var existingTable = new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
    ]);
    var existingSchema = new Schema([existingTable]);
    var commands = [
      MigrationBuilder.addColumnString("foo", new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'"), ""),
      MigrationBuilder.addColumnString("foo", new SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger,
          relatedColumnName: "xyz", relatedTableName: "abc", rule: ManagedRelationshipDeleteRule.cascade), "")
    ];

    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'"),
      new SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz", relatedTableName: "abc", rule: ManagedRelationshipDeleteRule.cascade)
    ]);
    var expectedSchema = new Schema([expectedTable]);

    var source = sourceForSchemaUpgrade(existingSchema, commands);
    var response = await runSource(source, existingSchema);
    var schema = new Schema.fromMap(response);
    expect(schema.differenceFrom(expectedSchema).hasDifferences, false);
  });

  test("Delete column", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'"),
      new SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz", relatedTableName: "abc", rule: ManagedRelationshipDeleteRule.cascade)
    ]);
    var existingSchema = new Schema([
      existingTable
    ]);

    var commands = [
      MigrationBuilder.deleteColumnString("foo", "ref", "")
    ];
    var expectedTable = new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'")
    ]);
    var expectedSchema = new Schema([expectedTable]);
    var source = sourceForSchemaUpgrade(existingSchema, commands);
    var response = await runSource(source, existingSchema);
    var schema = new Schema.fromMap(response);
    expect(schema.differenceFrom(expectedSchema).hasDifferences, false);
  });

  test("Alter column, many statements", () async {
    var existingTable = new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: null)
    ]);
    var existingSchema = new Schema([
      existingTable
    ]);

    var alteredColumn = new SchemaColumn.from(existingTable.columnForName("loaded"))
      ..isIndexed = false
      ..isNullable = false
      ..isUnique = false
      ..defaultValue = "'foo'";

    var commands = [
      MigrationBuilder.alterColumnString("foo", existingTable.columnForName("loaded"), alteredColumn, "")
    ];

    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      alteredColumn
    ]);
    var expectedSchema = new Schema([expectedTable]);
    var source = sourceForSchemaUpgrade(existingSchema, commands);
    var response = await runSource(source, existingSchema);
    var schema = new Schema.fromMap(response);
    expect(schema.differenceFrom(expectedSchema).hasDifferences, false);
  });

  test("Alter column, just one statement", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'")
    ]);
    var existingSchema = new Schema([
      existingTable
    ]);

    var alteredColumn = new SchemaColumn.from(existingTable.columnForName("loaded"))
      ..isIndexed = false;

    var commands = [
      MigrationBuilder.alterColumnString("foo", existingTable.columnForName("loaded"), alteredColumn, "")
    ];

    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      alteredColumn
    ]);
    var expectedSchema = new Schema([expectedTable]);
    var source = sourceForSchemaUpgrade(existingSchema, commands);
    var response = await runSource(source, existingSchema);
    var schema = new Schema.fromMap(response);
    expect(schema.differenceFrom(expectedSchema).hasDifferences, false);
  });

  test("Create table with uniqueSet", () async {
    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ], uniqueColumnSet: ["a", "b"]);

    var commands = [
      MigrationBuilder.createTableString(expectedTable, "")
    ];
    var source = sourceForSchemaUpgrade(new Schema.empty(), commands);
    print(source);
    var response = await runSource(source, new Schema([]));

    var schema = new Schema.fromMap(response);

    expect(schema.tables.length, 1);
    expect(expectedTable.differenceFrom(schema.tables.first).hasDifferences, false);
  });

  test("Alter table to add uniqueSet", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ]);
    var existingSchema = new Schema([
      existingTable
    ]);

    var alteredTable = new SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["a", "b"];

    var commands = [
      MigrationBuilder.alterTableString("foo", alteredTable)
      MigrationBuilder.alterColumnString("foo", existingTable.columnForName("loaded"), alteredColumn, "")
    ];

    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      alteredColumn
    ]);
    var expectedSchema = new Schema([expectedTable]);
    var source = sourceForSchemaUpgrade(existingSchema, commands);
    var response = await runSource(source, existingSchema);
    var schema = new Schema.fromMap(response);
    expect(schema.differenceFrom(expectedSchema).hasDifferences, false);
  });

  test("Alter table to remove uniqueSet", () async {

  });

  test("Alter table to modify uniqueSet", () async {

  });
}


String sourceForSchemaUpgrade(
    Schema existingSchema, List<String> commands) {
  var builder = new StringBuffer();
  builder.writeln("import 'package:aqueduct/aqueduct.dart';");
  builder.writeln("import 'dart:async';");
  builder.writeln("");
  builder.writeln("Future main(List<String> args, Map<String, dynamic> message) {");
  builder.writeln("  var sendPort = message['sendPort'];");
  builder.writeln("  var schema = message['schema'];");
  builder.writeln("  var database = new SchemaBuilder(null, new Schema.fromMap(schema));");
  commands.forEach((c) {
    builder.writeln("  $c");
  });
  builder.writeln("  sendPort.send(database.schema.asMap());");
  builder.writeln("}");

  return builder.toString();
}

Future<Map<String, dynamic>> runSource(String source, Schema fromSchema) async {
  var dataUri = Uri.parse(
      "data:application/dart;charset=utf-8,${Uri.encodeComponent(source)}");
  var completer = new Completer<Map>();
  var receivePort = new ReceivePort();
  receivePort.listen((msg) {
    completer.complete(msg);
  });

  var errPort = new ReceivePort()
    ..listen((msg) {
      throw new Exception(msg);
    });

  await Isolate.spawnUri(dataUri, [], {
    "sendPort": receivePort.sendPort,
    "schema": fromSchema.asMap()
  },
      onError: errPort.sendPort,
      packageConfig: new Uri.file(".packages"));

  var results = await completer.future;
  receivePort.close();
  errPort.close();
  return results;
}