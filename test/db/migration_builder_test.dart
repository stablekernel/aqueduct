import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:isolate_executor/isolate_executor.dart';
import 'package:test/test.dart';

void main() {
  test("Create table", () async {
    var expectedSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'"),
        new SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger,
            relatedColumnName: "xyz", relatedTableName: "abc", rule: DeleteRule.cascade)
      ]),
      new SchemaTable("abc", [new SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)])
    ]);

    await expectSchema(new Schema.empty(), becomesSchema: expectedSchema);
  });

  test("Delete table", () async {
    await expectSchema(
        new Schema([
          new SchemaTable("foo", [new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)]),
          new SchemaTable("donotdelete", [])
        ]),
        becomesSchema: new Schema([new SchemaTable("donotdelete", [])]));
  });

  test("Add column", () async {
    var existingSchema = new Schema([
      new SchemaTable("foo", [new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)])
    ]);

    var expectedSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'"),
        new SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger,
            relatedColumnName: "xyz", relatedTableName: "abc", rule: DeleteRule.cascade)
      ]),
      new SchemaTable("abc", [new SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)])
    ]);

    await expectSchema(existingSchema, becomesSchema: expectedSchema);
  });

  test("Delete column", () async {
    var existingSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'"),
        new SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger,
            relatedColumnName: "xyz", relatedTableName: "abc", rule: DeleteRule.cascade)
      ]),
      new SchemaTable("abc", [new SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)])
    ]);
    var expectedSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'")
      ]),
      new SchemaTable("abc", [new SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)])
    ]);

    await expectSchema(existingSchema, becomesSchema: expectedSchema);
  });

  test("Alter column, many statements", () async {
    var existingSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: null)
      ])
    ]);
    var expectedSchema = new Schema.from(existingSchema);
    expectedSchema.tableForName("foo").columnForName("loaded")
      ..isIndexed = false
      ..isNullable = false
      ..isUnique = false
      ..defaultValue = "'foo'";

    await expectSchema(existingSchema, becomesSchema: expectedSchema);
  });

  test("Alter column, just one statement", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true, isNullable: true, autoincrement: true, isUnique: true, defaultValue: "'foo'")
    ]);
    var alteredColumn = new SchemaColumn.from(existingTable.columnForName("loaded"))..isIndexed = false;

    var expectedTable = new SchemaTable(
        "foo", [new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true), alteredColumn]);

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([expectedTable]));
  });

  test("Create table with uniqueSet", () async {
    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ], uniqueColumnSetNames: [
      "a",
      "b"
    ]);

    await expectSchema(new Schema.empty(), becomesSchema: new Schema([expectedTable]));
  });

  test("Alter table to add uniqueSet", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ]);

    var alteredTable = new SchemaTable.from(existingTable)..uniqueColumnSet = ["a", "b"];

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([alteredTable]));
  });

  test("Alter table to remove uniqueSet", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ], uniqueColumnSetNames: [
      "a",
      "b"
    ]);

    var alteredTable = new SchemaTable.from(existingTable)..uniqueColumnSet = null;

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([alteredTable]));
  });

  test("Alter table to modify uniqueSet (same number of keys)", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
      new SchemaColumn("c", ManagedPropertyType.string),
    ], uniqueColumnSetNames: [
      "a",
      "b"
    ]);

    var alteredTable = new SchemaTable.from(existingTable)..uniqueColumnSet = ["b", "c"];

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([alteredTable]));
  });

  test("Alter table to modify uniqueSet (different number of keys)", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
      new SchemaColumn("c", ManagedPropertyType.string),
    ], uniqueColumnSetNames: [
      "a",
      "b"
    ]);

    var alteredTable = new SchemaTable.from(existingTable)..uniqueColumnSet = ["a", "b", "c"];

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([alteredTable]));
  });
}

Future expectSchema(Schema schema,
    {Schema becomesSchema, List<String> afterCommands, void alsoVerify(Schema createdSchema)}) async {
  var migrationSource = Migration.sourceForSchemaUpgrade(schema, becomesSchema, 1);
  migrationSource = migrationSource.split("\n").where((s) => !s.startsWith("import")).join("\n");

  final response = await IsolateExecutor.executeWithType(MigrateSchema,
      packageConfigURI: Directory.current.uri.resolve(".packages"),
      imports: MigrateSchema.imports,
      additionalContents: migrationSource,
      message: {"schema": schema.asMap()});

  var createdSchema = new Schema.fromMap(response);
  var diff = createdSchema.differenceFrom(becomesSchema);

  expect(diff.hasDifferences, false);

  if (alsoVerify != null) {
    alsoVerify(createdSchema);
  }
}

class MigrateSchema extends Executable {
  MigrateSchema(Map<String, dynamic> message)
      : schema = new Schema.fromMap(message["schema"]),
        super(message);

  final Schema schema;

  @override
  Future<dynamic> execute() async {
    final migration = instanceOf("Migration1");
    final outSchema = await Migration.schemaByApplyingMigrations([migration], fromSchema: schema);

    return outSchema.asMap();
  }

  static List<String> get imports => ["package:aqueduct/aqueduct.dart"];
}
