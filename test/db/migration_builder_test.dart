import 'dart:async';
import 'dart:isolate';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Create table", () async {
    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true,
          isNullable: true,
          autoincrement: true,
          isUnique: true,
          defaultValue: "'foo'"),
      new SchemaColumn.relationship(
          "ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz",
          relatedTableName: "abc",
          rule: ManagedRelationshipDeleteRule.cascade)
    ]);

    await expectSchema(new Schema.empty(),
        becomesSchema: new Schema([expectedTable]),
        afterCommands: [
          MigrationBuilder.createTableString(expectedTable, "")
        ]);
  });

  test("Delete table", () async {
    await expectSchema(new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
      ]),
      new SchemaTable("donotdelete", [])
    ]), becomesSchema: new Schema([
      new SchemaTable("donotdelete", [])
    ]), afterCommands: [
      MigrationBuilder.deleteTableString("foo", "")
    ]);
  });

  test("Add column", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
    ]);

    await expectSchema(new Schema([existingTable]),
      becomesSchema: new Schema([
        new SchemaTable("foo", [
          new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          new SchemaColumn("loaded", ManagedPropertyType.string,
              isIndexed: true,
              isNullable: true,
              autoincrement: true,
              isUnique: true,
              defaultValue: "'foo'"),
          new SchemaColumn.relationship(
              "ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz",
              relatedTableName: "abc",
              rule: ManagedRelationshipDeleteRule.cascade)
        ])
      ]),
      afterCommands: [
        MigrationBuilder.addColumnString(
            "foo", new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: "'foo'"), ""),
        MigrationBuilder.addColumnString("foo",
            new SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger,
                relatedColumnName: "xyz",
                relatedTableName: "abc",
                rule: ManagedRelationshipDeleteRule.cascade), "")
      ]);
  });

  test("Delete column", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true,
          isNullable: true,
          autoincrement: true,
          isUnique: true,
          defaultValue: "'foo'"),
      new SchemaColumn.relationship(
          "ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz",
          relatedTableName: "abc",
          rule: ManagedRelationshipDeleteRule.cascade)
    ]);

    await expectSchema(new Schema([existingTable]),
      becomesSchema: new Schema([
        new SchemaTable("foo", [
          new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          new SchemaColumn("loaded", ManagedPropertyType.string,
              isIndexed: true,
              isNullable: true,
              autoincrement: true,
              isUnique: true,
              defaultValue: "'foo'")
        ])
      ]),
      afterCommands: [
        MigrationBuilder.deleteColumnString("foo", "ref", "")
      ]);
  });

  test("Alter column, many statements", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true,
          isNullable: true,
          autoincrement: true,
          isUnique: true,
          defaultValue: null)
    ]);

    var alteredColumn = new SchemaColumn.from(
        existingTable.columnForName("loaded"))
      ..isIndexed = false
      ..isNullable = false
      ..isUnique = false
      ..defaultValue = "'foo'";

    await expectSchema(new Schema([existingTable]),
      becomesSchema: new Schema([new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        alteredColumn
      ])]),
      afterCommands: [
        MigrationBuilder.alterColumnString(
            "foo", existingTable.columnForName("loaded"), alteredColumn, "")
      ]);
  });

  test("Alter column, just one statement", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true,
          isNullable: true,
          autoincrement: true,
          isUnique: true,
          defaultValue: "'foo'")
    ]);
    var alteredColumn = new SchemaColumn.from(
        existingTable.columnForName("loaded"))
      ..isIndexed = false;

    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      alteredColumn
    ]);

    await expectSchema(new Schema([existingTable]),
        becomesSchema: new Schema([expectedTable]),
        afterCommands: [
          MigrationBuilder.alterColumnString(
              "foo", existingTable.columnForName("loaded"), alteredColumn, "")
        ]);
  });

  test("Create table with uniqueSet", () async {
    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ], uniqueColumnSetNames: ["a", "b"]);

    await expectSchema(new Schema.empty(),
      becomesSchema: new Schema([
        expectedTable
      ]), afterCommands: [
        MigrationBuilder.createTableString(expectedTable, "")
      ]);
  });

  test("Alter table to add uniqueSet", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ]);

    var alteredTable = new SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["a", "b"];

    await expectSchema(new Schema([existingTable]),
        becomesSchema: new Schema([alteredTable]), afterCommands: [
          MigrationBuilder.alterTableString(existingTable, alteredTable, "")
        ]);
  });

  test("Alter table to remove uniqueSet", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ], uniqueColumnSetNames: ["a", "b"]);

    var alteredTable = new SchemaTable.from(existingTable)
      ..uniqueColumnSet = null;

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([
      alteredTable
    ]), afterCommands: [
      MigrationBuilder.alterTableString(existingTable, alteredTable, "")
    ]);
  });

  test("Alter table to modify uniqueSet (same number of keys)", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
      new SchemaColumn("c", ManagedPropertyType.string),
    ], uniqueColumnSetNames: ["a", "b"]);

    var alteredTable = new SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["b", "c"];

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([
      alteredTable
    ]), afterCommands: [
      MigrationBuilder.alterTableString(existingTable, alteredTable, "")
    ]);
  });

  test("Alter table to modify uniqueSet (different number of keys)", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
      new SchemaColumn("c", ManagedPropertyType.string),
    ], uniqueColumnSetNames: ["a", "b"]);

    var alteredTable = new SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["a", "b", "c"];

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([
      alteredTable
    ]), afterCommands: [
      MigrationBuilder.alterTableString(existingTable, alteredTable, "")
    ]);
  });
}


String sourceForSchemaUpgrade(Schema existingSchema, List<String> commands) {
  var builder = new StringBuffer();
  builder.writeln("import 'package:aqueduct/aqueduct.dart';");
  builder.writeln("import 'dart:async';");
  builder.writeln("");
  builder.writeln(
      "Future main(List<String> args, Map<String, dynamic> message) {");
  builder.writeln("  var sendPort = message['sendPort'];");
  builder.writeln("  var schema = message['schema'];");
  builder.writeln(
      "  var database = new SchemaBuilder(null, new Schema.fromMap(schema));");
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

Future expectSchema(Schema schema,
    {Schema becomesSchema, List<String> afterCommands, void alsoVerify(
        Schema createdSchema)}) async {
  var source = sourceForSchemaUpgrade(schema, afterCommands);
  var response = await runSource(source, schema);
  var createdSchema = new Schema.fromMap(response);
  expect(createdSchema
      .differenceFrom(becomesSchema)
      .hasDifferences, false);
  if (alsoVerify != null) {
    alsoVerify(createdSchema);
  }
}