import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

/*
The purpose of these tests is to ensure that the SQL generated by diff'ing a schema creates the desired database.
These tests run queries against a database after it has been manipulated to ensure that the intended effect is met.
This is different than schema_generator_sql_mapping_test and generate_code_test. Those tests ensure a one-to-one mapping
between a builder command (e.g. createTable) and the generate SQL/Dart command.
 */

void main() {
  PostgreSQLPersistentStore store;

  setUp(() async {
    store = PostgreSQLPersistentStore(
        "dart", "dart", "localhost", 5432, "dart_test");
  });

  tearDown(() async {
    await store.close();
  });

  group("Tables", () {
    test("Add table to schema", () async {
      final cmds = await applyDifference(
          store,
          Schema.empty(),
          Schema([
            SchemaTable("foo", [
              SchemaColumn("id", ManagedPropertyType.integer,
                  isPrimaryKey: true)
            ])
          ]));

      expect(cmds.length, 1);

      final defs = await TableDefinition.get(store, ["foo"]);
      expect(defs["foo"].columns.length, 1);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);
    });

    test("Add multiple, unrelated tables", () async {
      final cmds = await applyDifference(
          store,
          Schema.empty(),
          Schema([
            SchemaTable("foo", [
              SchemaColumn("id", ManagedPropertyType.integer,
                  isPrimaryKey: true)
            ]),
            SchemaTable("bar", [
              SchemaColumn("id", ManagedPropertyType.integer,
                  isPrimaryKey: true)
            ])
          ]));

      expect(cmds.length, 2);

      final defs = await TableDefinition.get(store, ["foo", "bar"]);

      expect(defs["foo"].columns.length, 1);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);

      expect(defs["bar"].columns.length, 1);
      defs["bar"].expectColumn("id", "integer", primaryKey: true);
    });

    test("Delete multiple, unrelated tables", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          SchemaTable("bar", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ])
        ]),
        Schema.empty()
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["foo", "bar"]);

      expect(defs["foo"].columns.length, 1);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);

      expect(defs["bar"].columns.length, 1);
      defs["bar"].expectColumn("id", "integer", primaryKey: true);

      await applyDifference(store, schemas[1], schemas[2]);
      defs = await TableDefinition.get(store, ["foo", "bar"]);
      expect(defs.length, 0);
    });

    test("Add unique constraint to table", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("a", ManagedPropertyType.integer)
          ]),
        ]),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("a", ManagedPropertyType.integer),
            SchemaColumn("b", ManagedPropertyType.integer, isNullable: true),
          ], uniqueColumnSetNames: [
            "a",
            "b"
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["u"]);
      expect(defs["u"].uniqueSet, isNull);

      await applyDifference(store, schemas[1], schemas[2]);
      defs = await TableDefinition.get(store, ["u"]);
      expect(defs["u"].uniqueSet, ["a", "b"]);
    });

    test("Remove unique constraint from table", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("a", ManagedPropertyType.integer),
            SchemaColumn("b", ManagedPropertyType.integer)
          ], uniqueColumnSetNames: [
            "a",
            "b"
          ]),
        ]),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("a", ManagedPropertyType.integer),
            SchemaColumn("b", ManagedPropertyType.integer),
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["u"]);
      expect(defs["u"].uniqueSet, ["a", "b"]);

      await applyDifference(store, schemas[1], schemas[2]);
      defs = await TableDefinition.get(store, ["u"]);
      expect(defs["u"].uniqueSet, isNull);
    });

    test("Modify unique constraint on table", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("a", ManagedPropertyType.integer),
            SchemaColumn("b", ManagedPropertyType.integer)
          ], uniqueColumnSetNames: [
            "a",
            "b"
          ]),
        ]),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("a", ManagedPropertyType.integer),
            SchemaColumn("b", ManagedPropertyType.integer),
            SchemaColumn("c", ManagedPropertyType.integer, isNullable: true)
          ], uniqueColumnSetNames: [
            "b",
            "c"
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["u"]);
      expect(defs["u"].uniqueSet, ["a", "b"]);

      await applyDifference(store, schemas[1], schemas[2]);
      defs = await TableDefinition.get(store, ["u"]);
      expect(defs["u"].uniqueSet, ["b", "c"]);
    });
  });

  group("Columns (no relationship)", () {
    test("Add column", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.string)
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);

      await applyDifference(store, schemas[1], schemas[2]);
      defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);
      defs["foo"].expectColumn("x", "text");
    });

    test("Add multiple columns", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.string),
            SchemaColumn("y", ManagedPropertyType.datetime,
                isIndexed: true,
                isNullable: true,
                isUnique: true,
                defaultValue: "'1900-01-01 00:00:00'")
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);

      await applyDifference(store, schemas[1], schemas[2]);
      defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);
      defs["foo"].expectColumn("x", "text");
      defs["foo"].expectColumn("y", "timestamp without time zone",
          defaultValue: "'1900-01-01 00:00:00'::timestamp without time zone",
          nullable: true,
          indexed: true,
          unique: true);
    });

    test("Add column with autoincrementing", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger,
                autoincrement: true),
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      final defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);
      defs["foo"].expectColumn("x", "bigint", autoincrementing: true);
    });

    test("Delete column", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      final defs = await TableDefinition.get(store, ["foo"]);
      expect(defs["foo"].columns.length, 1);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);
    });

    test("Delete multiple columns", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger),
            SchemaColumn("y", ManagedPropertyType.document),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      final defs = await TableDefinition.get(store, ["foo"]);
      expect(defs["foo"].columns.length, 1);
      defs["foo"].expectColumn("id", "integer", primaryKey: true);
    });

    // perform operations on multiple columns - esp. to get scenarios where unique and index are mixed

    test("Modify index", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger, isIndexed: false),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger, isIndexed: true),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger, isIndexed: false),
          ]),
        ]),
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      var defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("x", "bigint", indexed: true);

      await applyDifference(store, schemas[2], schemas[3]);
      defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("x", "bigint", indexed: false);
    });

    test("Modify defaultValue", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger,
                defaultValue: null),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger,
                defaultValue: "1"),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger,
                defaultValue: null),
          ]),
        ]),
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      var defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("x", "bigint", defaultValue: "1");

      await applyDifference(store, schemas[2], schemas[3]);
      defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("x", "bigint", defaultValue: null);
    });

    test("Modify unique", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger, isUnique: false),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger, isUnique: true),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger, isUnique: false),
          ]),
        ]),
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      var defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("x", "bigint", unique: true);

      await applyDifference(store, schemas[2], schemas[3]);
      defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("x", "bigint", unique: false);
    });

    test("Modify nullability", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger,
                isNullable: false),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger, isNullable: true),
          ]),
        ]),
        Schema([
          SchemaTable("foo", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.bigInteger,
                isNullable: false),
          ]),
        ]),
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      var defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("x", "bigint", nullable: true);

      await applyDifference(store, schemas[2], schemas[3]);
      defs = await TableDefinition.get(store, ["foo"]);
      defs["foo"].expectColumn("x", "bigint", nullable: false);
    });
  });

  group("Relationships", () {
    test("Add tables, one with a foreign key to another", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                relatedTableName: "t", relatedColumnName: "id")
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer",
          nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "SET NULL");
    });

    test("In reverse order, add tables, one with a foreign key to another", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
              relatedTableName: "t", relatedColumnName: "id")
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer",
        nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "SET NULL");
    });

    test("Add tables with foreign key references to one another", () async {},
        skip: "nyi");

    test("Add table with foreign key reference to itself", () async {},
        skip: "nyi");

    test("Add 3 tables with cyclical foreign keys", () async {}, skip: "nyi");

    test("Add a table with a foreign key to an existing table", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                relatedTableName: "t", relatedColumnName: "id")
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);

      var defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer",
          nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "SET NULL");
    });

    test(
        "Add a new table and a foreign key from an existing table to the new table",
        () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                relatedTableName: "t", relatedColumnName: "id")
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer",
          nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "SET NULL");
    });

    test("Add a new foreign key column", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                relatedTableName: "t", relatedColumnName: "id")
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer",
          nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "SET NULL");
    });

    test("Add a new unique (has-one) foreign key column", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
              relatedTableName: "t", relatedColumnName: "id", isUnique: true)
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer",
        nullable: true, relatedTableName: "t", relatedColumnName: "id", unique: true, deleteRule: "SET NULL");
    });

    test("Remove foreign key column", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
              relatedTableName: "t", relatedColumnName: "id")
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await applyDifference(store, schemas[1], schemas[2]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      expect(defs["u"].columns.length, 1);
      expect(defs["u"].columns.first.name, "id");
    });

    test("Remove foreign key column after rows have already been inserted", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
              relatedTableName: "t", relatedColumnName: "id")
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      await store.execute("INSERT INTO t (id) VALUES (1)");
      await store.execute("INSERT INTO u (id, ref_id) VALUES (1,1)");
      await applyDifference(store, schemas[1], schemas[2]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      expect(defs["u"].columns.length, 1);
      expect(defs["u"].columns.first.name, "id");
    });

    test("Modify delete rule", () async {
      final base = Schema([
        SchemaTable("u", [
          SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          SchemaColumn.relationship("ref", ManagedPropertyType.integer,
            relatedTableName: "t", relatedColumnName: "id")
        ]),
        SchemaTable("t", [
          SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        ]),
      ]);

      final schemas = [
        Schema.empty(),
        base,
        Schema.from(base)..tableForName("u").columnForName("ref").deleteRule = DeleteRule.cascade,
        Schema.from(base)..tableForName("u").columnForName("ref").deleteRule = DeleteRule.restrict,
        Schema.from(base)..tableForName("u").columnForName("ref").deleteRule = DeleteRule.setDefault,
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer", nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "SET NULL");

      await applyDifference(store, schemas[1], schemas[2]);
      defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer", nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "CASCADE");

      await applyDifference(store, schemas[2], schemas[3]);
      defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer", nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "RESTRICT");

      await applyDifference(store, schemas[3], schemas[4]);
      defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer", nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "SET DEFAULT");
    });

    test("Modify foreign key nullability", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
              relatedTableName: "t", relatedColumnName: "id")
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
        Schema([
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
              relatedTableName: "t", relatedColumnName: "id", rule: DeleteRule.cascade, isNullable: false)
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer", nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "SET NULL");

      await applyDifference(store, schemas[1], schemas[2]);
      defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer", nullable: false, relatedTableName: "t", relatedColumnName: "id", deleteRule: "CASCADE");
    });

    test("Delete tables that have a relationship", () async {
      final schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("v", [SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)]),
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
              relatedTableName: "t", relatedColumnName: "id")
          ]),
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
        Schema([
          SchemaTable("v", [SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)]),
        ])
      ];

      await applyDifference(store, schemas[0], schemas[1]);
      var defs = await TableDefinition.get(store, ["t", "u"]);
      defs["u"].expectColumn("ref_id", "integer", nullable: true, relatedTableName: "t", relatedColumnName: "id", deleteRule: "SET NULL");

      await applyDifference(store, schemas[1], schemas[2]);
      defs = await TableDefinition.get(store, ["t", "u", "v"]);
      expect(defs.length, 1);
      expect(defs.containsKey("v"), true);
    });
  });
}

Future<List<String>> applyDifference(
    PersistentStore store, Schema baseSchema, Schema newSchema) async {
  final diff = baseSchema.differenceFrom(newSchema);
  final commands =
      SchemaBuilder.fromDifference(store, diff, isTemporary: true).commands;

  await Future.forEach(commands, (String c) => store.execute(c));

  return commands;
}

class TableDefinition {
  TableDefinition(this.name);

  static Future<Map<String, TableDefinition>> get(
      PostgreSQLPersistentStore store, List<String> tableNames) async {
    final tables = await Future.wait(tableNames.map((t) async {
      final def = TableDefinition(t);
      await def.resolve(store);
      return def;
    }));

    final m = <String, TableDefinition>{};
    tables.forEach((t) {
      if (t.isValid) {
        m[t.name] = t;
      }
    });

    return m;
  }

  void expectColumn(String name, String dataType,
      {String defaultValue,
      bool unique = false,
      bool primaryKey = false,
      bool nullable = false,
      bool indexed = false,
      bool autoincrementing = false,
      String relatedTableName,
      String relatedColumnName,
      String deleteRule}) {
    final col = columns.firstWhere((c) => c.name == name,
        orElse: () => fail("column $name doesn't exist"));

    expect(col.dataType, dataType, reason: "$name data type");
    expect(col.defaultValue, defaultValue, reason: "$name default value");
    expect(col.isPrimaryKey, primaryKey, reason: "$name primary key");
    expect(col.isNullable, nullable, reason: "$name nullable");
    expect(col.isAutoincrementing, autoincrementing, reason: "$name autoincrement");

    // if column is expected to be a pk, it is always indexed and unique.
    // if column is relationship, it is always indexed
    if (primaryKey) {

    } else if (relatedTableName != null || relatedColumnName != null) {
      expect(col.isIndexed, true, reason: "$name indexed");
      expect(col.isUnique, unique, reason: "$name unique");
    } else {
      expect(col.isIndexed, indexed, reason: "$name indexed");
      expect(col.isUnique, unique, reason: "$name unique");
    }

    expect(col.relatedColumnName, relatedColumnName, reason: "$name related column name");
    expect(col.relatedTableName, relatedTableName, reason: "$name related table name");
    expect(col.deleteRule, deleteRule, reason: "$name delete rule");
  }

  final String name;
  List<ColumnDefinition> columns;
  bool isValid;

  List<String> uniqueSet;

  Future<void> resolve(PostgreSQLPersistentStore store) async {
    final List<List<dynamic>> exists = await store.execute(
        "SELECT table_name FROM information_schema.tables WHERE table_name = '$name'");
    isValid = exists.length == 1;

    if (!isValid) {
      return;
    }

    final List<List<dynamic>> results = await store.execute(
        "SELECT column_name, column_default, data_type, is_nullable FROM information_schema.columns WHERE table_name = '$name'");

    columns = results.map((row) => ColumnDefinition(row)).toList();

    final List<List<dynamic>> constraints = await store.execute(
        "SELECT c.column_name, t.constraint_type FROM information_schema.key_column_usage AS c "
        "LEFT JOIN information_schema.table_constraints AS t ON t.constraint_name = c.constraint_name WHERE t.table_name = '$name'");
    constraints.forEach((constraint) {
      final col = columns.firstWhere((c) => c.name == constraint.first);

      if (constraint.last == "UNIQUE") {
        col.isUnique = true;
      } else if (constraint.last == "PRIMARY KEY") {
        col.isPrimaryKey = true;
      }
    });

    final List<List<dynamic>> indices = await store
        .execute("SELECT indexdef FROM pg_indexes WHERE tablename = '$name'");
    final lookupIndex = RegExp(
        "CREATE INDEX ([A-Za-z_]*) ON [A-Za-z_0-9\\.]* USING [A-Za-z_]* \\(([a-zA-Z0-9_]*)\\)");
    final uniqueIndex = RegExp(
        "CREATE UNIQUE INDEX ([A-Za-z_]*) ON [A-Za-z_0-9\\.]* USING [A-Za-z_]* \\(([a-zA-Z0-9_, ]*)\\)");
    indices.forEach((idx) {
      final lMatch = lookupIndex.firstMatch(idx.first as String);
      if (lMatch != null) {
        final columnName = lMatch.group(2);
        columns.firstWhere((c) => c.name == columnName).isIndexed = true;
      }

      final uMatch = uniqueIndex.firstMatch(idx.first as String);
      if (uMatch != null) {
        final columnNames =
            uMatch.group(2).split(",").map((s) => s.trim()).toList();
        if (columnNames.length == 1) {
          columns.firstWhere((c) => c.name == columnNames.first).isUnique =
              true;
        } else {
          uniqueSet = columnNames;
        }
      }
    });

    final List<List<dynamic>> foreignKeys = await store.execute(
        "SELECT ccu.table_name, ccu.column_name, kcu.column_name, rc.delete_rule FROM information_schema.table_constraints tc "
        "INNER JOIN information_schema.referential_constraints rc ON (tc.constraint_name=rc.constraint_name) "
        "INNER JOIN information_schema.key_column_usage kcu ON (tc.constraint_name=kcu.constraint_name) "
        "INNER JOIN information_schema.constraint_column_usage ccu ON (tc.constraint_name=ccu.constraint_name) "
        "WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_name ='$name';");
    foreignKeys.forEach((foreignKey) {
      final col = columns.firstWhere((c) => c.name == foreignKey[2]);

      col.relatedTableName = foreignKey[0] as String;
      col.relatedColumnName = foreignKey[1] as String;
      col.deleteRule = foreignKey[3] as String;
    });
  }
}

class ColumnDefinition {
  ColumnDefinition(List<dynamic> row) {
    name = row[0] as String;
    dataType = row[2] as String;
    isNullable = row[3] == "YES";

    final def = row[1] as String;
    if (def?.startsWith("nextval") ?? false) {
      isAutoincrementing = true;
    } else if (def != null) {
      defaultValue = def;
    }
  }

  String relatedTableName;
  String relatedColumnName;
  String deleteRule;

  // default = 'value'::type
  String defaultValue;

  // text, timestamp without time zone, jsonb, etc.
  String name;
  String dataType;
  bool isUnique = false;
  bool isPrimaryKey = false;
  bool isNullable;
  bool isIndexed = false;
  bool isAutoincrementing = false;
}
