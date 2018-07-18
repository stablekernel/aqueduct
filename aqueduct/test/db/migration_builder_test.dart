import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:isolate_executor/isolate_executor.dart';
import 'package:test/test.dart';

void main() {
  test("Create table", () async {
    var expectedSchema = Schema([
      SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: "'foo'"),
        SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger,
            relatedColumnName: "xyz",
            relatedTableName: "abc",
            rule: DeleteRule.cascade)
      ]),
      SchemaTable("abc", [
        SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)
      ])
    ]);

    await expectSchema(Schema.empty(), becomesSchema: expectedSchema);
  });

  test("Delete table", () async {
    await expectSchema(
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          SchemaTable("donotdelete", [])
        ]),
        becomesSchema: Schema([SchemaTable("donotdelete", [])]));
  });

  test("Add column", () async {
    var existingSchema = Schema([
      SchemaTable("foo",
          [SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)])
    ]);

    var expectedSchema = Schema([
      SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: "'foo'"),
        SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger,
            relatedColumnName: "xyz",
            relatedTableName: "abc",
            rule: DeleteRule.cascade)
      ]),
      SchemaTable("abc", [
        SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)
      ])
    ]);

    await expectSchema(existingSchema, becomesSchema: expectedSchema);
  });

  test("Delete column", () async {
    var existingSchema = Schema([
      SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: "'foo'"),
        SchemaColumn.relationship("ref", ManagedPropertyType.bigInteger,
            relatedColumnName: "xyz",
            relatedTableName: "abc",
            rule: DeleteRule.cascade)
      ]),
      SchemaTable("abc", [
        SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)
      ])
    ]);
    var expectedSchema = Schema([
      SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: "'foo'")
      ]),
      SchemaTable("abc", [
        SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)
      ])
    ]);

    await expectSchema(existingSchema, becomesSchema: expectedSchema);
  });

  test("Alter column, many statements", () async {
    var existingSchema = Schema([
      SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: null)
      ])
    ]);
    var expectedSchema = Schema.from(existingSchema);
    expectedSchema.tableForName("foo").columnForName("loaded")
      ..isIndexed = false
      ..isNullable = false
      ..isUnique = false
      ..defaultValue = "'foo'";

    await expectSchema(existingSchema, becomesSchema: expectedSchema);
  });

  test("Alter column, just one statement", () async {
    var existingTable = SchemaTable("foo", [
      SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true,
          isNullable: true,
          autoincrement: true,
          isUnique: true,
          defaultValue: "'foo'")
    ]);
    var alteredColumn = SchemaColumn.from(existingTable.columnForName("loaded"))
      ..isIndexed = false;

    var expectedTable = SchemaTable("foo", [
      SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      alteredColumn
    ]);

    await expectSchema(Schema([existingTable]),
        becomesSchema: Schema([expectedTable]));
  });

  test("Create table with uniqueSet", () async {
    var expectedTable = SchemaTable("foo", [
      SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      SchemaColumn("a", ManagedPropertyType.string),
      SchemaColumn("b", ManagedPropertyType.string),
    ], uniqueColumnSetNames: [
      "a",
      "b"
    ]);

    await expectSchema(Schema.empty(), becomesSchema: Schema([expectedTable]));
  });

  test("Alter table to add uniqueSet", () async {
    var existingTable = SchemaTable("foo", [
      SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      SchemaColumn("a", ManagedPropertyType.string),
      SchemaColumn("b", ManagedPropertyType.string),
    ]);

    var alteredTable = SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["a", "b"];

    await expectSchema(Schema([existingTable]),
        becomesSchema: Schema([alteredTable]));
  });

  test("Alter table to remove uniqueSet", () async {
    var existingTable = SchemaTable("foo", [
      SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      SchemaColumn("a", ManagedPropertyType.string),
      SchemaColumn("b", ManagedPropertyType.string),
    ], uniqueColumnSetNames: [
      "a",
      "b"
    ]);

    var alteredTable = SchemaTable.from(existingTable)..uniqueColumnSet = null;

    await expectSchema(Schema([existingTable]),
        becomesSchema: Schema([alteredTable]));
  });

  test("Alter table to modify uniqueSet (same number of keys)", () async {
    var existingTable = SchemaTable("foo", [
      SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      SchemaColumn("a", ManagedPropertyType.string),
      SchemaColumn("b", ManagedPropertyType.string),
      SchemaColumn("c", ManagedPropertyType.string),
    ], uniqueColumnSetNames: [
      "a",
      "b"
    ]);

    var alteredTable = SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["b", "c"];

    await expectSchema(Schema([existingTable]),
        becomesSchema: Schema([alteredTable]));
  });

  test("Alter table to modify uniqueSet (different number of keys)", () async {
    var existingTable = SchemaTable("foo", [
      SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      SchemaColumn("a", ManagedPropertyType.string),
      SchemaColumn("b", ManagedPropertyType.string),
      SchemaColumn("c", ManagedPropertyType.string),
    ], uniqueColumnSetNames: [
      "a",
      "b"
    ]);

    var alteredTable = SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["a", "b", "c"];

    await expectSchema(Schema([existingTable]),
        becomesSchema: Schema([alteredTable]));
  });
}

Future expectSchema(Schema schema,
    {Schema becomesSchema,
    List<String> afterCommands,
    void alsoVerify(Schema createdSchema)}) async {
  var migrationSource =
      Migration.sourceForSchemaUpgrade(schema, becomesSchema, 1);
  migrationSource = migrationSource
      .split("\n")
      .where((s) => !s.startsWith("import"))
      .join("\n");

  final functionSource = (reflect(schemaByApplyingMigrations) as ClosureMirror).function.source;
  final contents = "$migrationSource\n${functionSource}";

  final response = await IsolateExecutor.run(MigrateSchema.input(schema),
      packageConfigURI: Directory.current.uri.resolve(".packages"),
      imports: MigrateSchema.imports,
      additionalContents: contents);

  var createdSchema = Schema.fromMap(response);
  var diff = createdSchema.differenceFrom(becomesSchema);

  expect(diff.hasDifferences, false);

  if (alsoVerify != null) {
    alsoVerify(createdSchema);
  }
}

class MigrateSchema extends Executable<Map<String, dynamic>> {
  MigrateSchema(Map<String, dynamic> message)
      : schema = Schema.fromMap(message["schema"] as Map<String, dynamic>),
        super(message);

  MigrateSchema.input(this.schema) : super({"schema": schema.asMap()});

  final Schema schema;

  @override
  Future<Map<String, dynamic>> execute() async {
    final migration = instanceOf("Migration1") as Migration;
    final outSchema =
        await schemaByApplyingMigrations([migration], fromSchema: schema);

    return outSchema.asMap();
  }

  static List<String> get imports => ["package:aqueduct/aqueduct.dart"];
}

Future<Schema> schemaByApplyingMigrations(List<Migration> migrations,
    {Schema fromSchema}) async {
  final builder = SchemaBuilder(null, fromSchema ?? Schema.empty());
  for (var migration in migrations) {
    migration.database = builder;
    await migration.upgrade();
  }
  return builder.schema;
}
