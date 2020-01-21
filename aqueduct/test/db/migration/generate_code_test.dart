import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

/*
These tests ensure that a SchemaBuilder generates equivalent Dart expressions, that when those expressions
are executed in a script, would recreate the same invocations applied to the generating SchemaBuilder.
 */

final List<SchemaColumn> columnsWithAllAttributeOptions = [
  SchemaColumn("id", ManagedPropertyType.integer,
      isPrimaryKey: true,
      autoincrement: true,
      defaultValue: null,
      isIndexed: true,
      isNullable: false,
      isUnique: false),
  SchemaColumn("t", ManagedPropertyType.string,
      isPrimaryKey: false,
      autoincrement: false,
      defaultValue: '\'x\'',
      isIndexed: false,
      isNullable: true,
      isUnique: true),
];

final List<String> dartExpressionForColumnsWithAllAttributeOptions = [
  "SchemaColumn(\"id\", ManagedPropertyType.integer, isPrimaryKey: true, autoincrement: true, isIndexed: true, isNullable: false, isUnique: false)",
  "SchemaColumn(\"t\", ManagedPropertyType.string, isPrimaryKey: false, autoincrement: false, defaultValue: \"'x'\", isIndexed: false, isNullable: true, isUnique: true)"
];

void main() {
  SchemaBuilder builder;

  setUp(() {
    builder = SchemaBuilder(null, Schema.empty());
  });

  group("Create table", () {
    test("Create basic table", () {
      builder.createTable(SchemaTable("foo", columnsWithAllAttributeOptions));

      expect(builder.commands.length, 1);
      expect(
          builder.commands.first,
          "database.createTable(SchemaTable(\"foo\", ["
          "${dartExpressionForColumnsWithAllAttributeOptions[0]},${dartExpressionForColumnsWithAllAttributeOptions[1]}]));");
    });

    test("Create table with unique constraints", () {
      builder.createTable(SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer),
        SchemaColumn("x", ManagedPropertyType.integer)
      ], uniqueColumnSetNames: [
        "id",
        "x"
      ]));

      expect(builder.commands.length, 1);
      expect(
          builder.commands.first,
          "database.createTable(SchemaTable(\"foo\", ["
          "SchemaColumn(\"id\", ManagedPropertyType.integer, isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),"
          "SchemaColumn(\"x\", ManagedPropertyType.integer, isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false)"
          "], uniqueColumnSetNames: [\"id\",\"x\"]));");
    });
  });

  test("Delete table", () {
    builder.createTable(
        SchemaTable("foo", [SchemaColumn("id", ManagedPropertyType.integer)]));
    builder.deleteTable("foo");
    expect(builder.commands.length, 2);
    expect(builder.commands.last, "database.deleteTable(\"foo\");");
  });

  test("Rename table", () {
    builder.createTable(
        SchemaTable("foo", [SchemaColumn("id", ManagedPropertyType.integer)]));
    builder.renameTable("foo", "bar");
    expect(builder.commands.length, 2);
    expect(builder.commands.last, "database.renameTable(\"foo\", \"bar\");");
  }, skip: "not yet implemented");

  group("Alter table", () {
    test("Alter table; change unique", () {
      builder.createTable(SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer),
        SchemaColumn("x", ManagedPropertyType.integer),
        SchemaColumn("y", ManagedPropertyType.integer)
      ], uniqueColumnSetNames: [
        "id",
        "x"
      ]));
      builder.alterTable("foo", (t) {
        t.uniqueColumnSet = ["x", "y"];
      });
      expect(builder.commands.length, 2);
      expect(builder.commands.last,
          "database.alterTable(\"foo\", (t) {t.uniqueColumnSet = [\"x\",\"y\"];});");
    });

    test("Alter table; add unique", () {
      builder.createTable(SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer),
        SchemaColumn("x", ManagedPropertyType.integer),
        SchemaColumn("y", ManagedPropertyType.integer)
      ]));
      builder.alterTable("foo", (t) {
        t.uniqueColumnSet = ["x", "y"];
      });
      expect(builder.commands.length, 2);
      expect(builder.commands.last,
          "database.alterTable(\"foo\", (t) {t.uniqueColumnSet = [\"x\",\"y\"];});");
    });

    test("Alter table; delete unique", () {
      builder.createTable(SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer),
        SchemaColumn("x", ManagedPropertyType.integer),
        SchemaColumn("y", ManagedPropertyType.integer)
      ], uniqueColumnSetNames: [
        "id",
        "x"
      ]));
      builder.alterTable("foo", (t) {
        t.uniqueColumnSet = null;
      });
      expect(builder.commands.length, 2);
      expect(builder.commands.last,
          "database.alterTable(\"foo\", (t) {t.uniqueColumnSet = null;});");
    });
  });

  group("Add column", () {
    test("Add column", () {
      builder.createTable(SchemaTable(
          "foo", [SchemaColumn("id", ManagedPropertyType.integer)]));
      builder.addColumn("foo",
          SchemaColumn("x", ManagedPropertyType.integer, isNullable: true));
      expect(builder.commands.length, 2);
      expect(
          builder.commands.last,
          "database.addColumn(\"foo\", "
          "SchemaColumn(\"x\", ManagedPropertyType.integer, isPrimaryKey: false, autoincrement: false, "
          "isIndexed: false, isNullable: true, isUnique: false));");
    });

    test("Add multiple columns", () {
      builder.createTable(SchemaTable(
          "foo", [SchemaColumn("id", ManagedPropertyType.integer)]));
      builder.addColumn("foo", SchemaColumn("x", ManagedPropertyType.integer));
      builder.addColumn("foo",
          SchemaColumn("y", ManagedPropertyType.integer, defaultValue: "2"));
      expect(builder.commands.length, 3);
      expect(
          builder.commands[1],
          "database.addColumn(\"foo\", "
          "SchemaColumn(\"x\", ManagedPropertyType.integer, isPrimaryKey: false, autoincrement: false, "
          "isIndexed: false, isNullable: false, isUnique: false));");
      expect(
          builder.commands[2],
          "database.addColumn(\"foo\", "
          "SchemaColumn(\"y\", ManagedPropertyType.integer, isPrimaryKey: false, autoincrement: false, "
          "defaultValue: \"2\", isIndexed: false, isNullable: false, isUnique: false));");
    });

    test("Add relationship column", () {
      builder.createTable(SchemaTable(
          "foo", [SchemaColumn("id", ManagedPropertyType.integer)]));
      builder.createTable(SchemaTable(
          "bar", [SchemaColumn("id", ManagedPropertyType.integer)]));
      builder.addColumn(
          "bar",
          SchemaColumn.relationship("foo_id", ManagedPropertyType.integer,
              relatedTableName: "foo", relatedColumnName: "id"));
      expect(builder.commands.length, 3);
      expect(
          builder.commands.last,
          "database.addColumn(\"bar\", "
          "SchemaColumn.relationship(\"foo_id\", ManagedPropertyType.integer, relatedTableName: \"foo\", relatedColumnName: \"id\", rule: DeleteRule.nullify, isNullable: true, isUnique: false));");
    });
  });

  test("Delete column", () {
    builder.createTable(
        SchemaTable("foo", [SchemaColumn("id", ManagedPropertyType.integer)]));
    builder.addColumn("foo", SchemaColumn("x", ManagedPropertyType.integer));
    builder.deleteColumn("foo", "x");
    expect(builder.commands.length, 3);
    expect(builder.commands.last, "database.deleteColumn(\"foo\", \"x\");");
  });

  test("Rename column", () {}, skip: "not yet implemented");

  group("Alter column", () {
    test("isIndexed", () {
      builder.createTable(SchemaTable("foo",
          [SchemaColumn("id", ManagedPropertyType.integer, isIndexed: false)]));
      builder.alterColumn("foo", "id", (c) {
        c.isIndexed = true;
      });
      expect(builder.commands.length, 2);
      expect(builder.commands.last,
          "database.alterColumn(\"foo\", \"id\", (c) {c.isIndexed = true;});");

      builder.alterColumn("foo", "id", (c) {
        c.isIndexed = false;
      });
      expect(builder.commands.length, 3);
      expect(builder.commands.last,
          "database.alterColumn(\"foo\", \"id\", (c) {c.isIndexed = false;});");

      builder.alterColumn("foo", "id", (c) {
        c.isIndexed = false;
      });
      expect(builder.commands.length, 3);
    });

    test("defaultValue", () {
      builder.createTable(SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer, defaultValue: null)
      ]));
      builder.alterColumn("foo", "id", (c) {
        c.defaultValue = "'foobar'";
      });
      expect(builder.commands.length, 2);
      expect(builder.commands.last,
          'database.alterColumn("foo", "id", (c) {c.defaultValue = "\'foobar\'";});');

      builder.alterColumn("foo", "id", (c) {
        c.defaultValue = "'foobar'";
      });
      expect(builder.commands.length, 2);

      builder.alterColumn("foo", "id", (c) {
        c.defaultValue = null;
      });
      expect(builder.commands.length, 3);
      expect(builder.commands.last,
          "database.alterColumn(\"foo\", \"id\", (c) {c.defaultValue = null;});");

      builder.alterColumn("foo", "id", (c) {
        c.defaultValue = null;
      });
      expect(builder.commands.length, 3);
    });

    test("isUnique", () {
      builder.createTable(SchemaTable("foo",
          [SchemaColumn("id", ManagedPropertyType.integer, isUnique: false)]));
      builder.alterColumn("foo", "id", (c) {
        c.isUnique = true;
      });
      expect(builder.commands.length, 2);
      expect(builder.commands.last,
          "database.alterColumn(\"foo\", \"id\", (c) {c.isUnique = true;});");

      builder.alterColumn("foo", "id", (c) {
        c.isUnique = false;
      });
      expect(builder.commands.length, 3);
      expect(builder.commands.last,
          "database.alterColumn(\"foo\", \"id\", (c) {c.isUnique = false;});");

      builder.alterColumn("foo", "id", (c) {
        c.isUnique = false;
      });
      expect(builder.commands.length, 3);
    });

    test("isNullable", () {
      builder.createTable(SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer, isNullable: false)
      ]));
      builder.alterColumn("foo", "id", (c) {
        c.isNullable = true;
      });
      expect(builder.commands.length, 2);
      expect(builder.commands.last,
          "database.alterColumn(\"foo\", \"id\", (c) {c.isNullable = true;});");

      builder.alterColumn("foo", "id", (c) {
        c.isNullable = false;
      });
      expect(builder.commands.length, 3);
      expect(builder.commands.last,
          "database.alterColumn(\"foo\", \"id\", (c) {c.isNullable = false;});");

      builder.alterColumn("foo", "id", (c) {
        c.isNullable = false;
      });
      expect(builder.commands.length, 3);
    });

    test("isNullable foreign key", () {
      builder.createTable(SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer, isNullable: false)
      ]));
      builder.createTable(SchemaTable("bar", [
        SchemaColumn("id", ManagedPropertyType.integer),
        SchemaColumn.relationship("foo_id", ManagedPropertyType.integer,
            isNullable: false, relatedTableName: "foo", relatedColumnName: "id")
      ]));
      builder.alterColumn("bar", "foo_id", (c) {
        c.isNullable = true;
      });
      expect(builder.commands.length, 3);
      expect(builder.commands.last,
          "database.alterColumn(\"bar\", \"foo_id\", (c) {c.isNullable = true;});");

      builder.alterColumn("bar", "foo_id", (c) {
        c.isNullable = false;
      });
      expect(builder.commands.length, 4);
      expect(builder.commands.last,
          "database.alterColumn(\"bar\", \"foo_id\", (c) {c.isNullable = false;});");

      builder.alterColumn("bar", "foo_id", (c) {
        c.isNullable = false;
      });
      expect(builder.commands.length, 4);
    });

    test("deleteRule", () {
      builder.createTable(SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer, isNullable: false)
      ]));
      builder.createTable(SchemaTable("bar", [
        SchemaColumn("id", ManagedPropertyType.integer),
        SchemaColumn.relationship("foo_id", ManagedPropertyType.integer,
            relatedTableName: "foo",
            relatedColumnName: "id",
            rule: DeleteRule.cascade)
      ]));
      builder.alterColumn("bar", "foo_id", (c) {
        c.deleteRule = DeleteRule.nullify;
      });
      expect(builder.commands.length, 3);
      expect(builder.commands.last,
          "database.alterColumn(\"bar\", \"foo_id\", (c) {c.deleteRule = DeleteRule.nullify;});");

      builder.alterColumn("bar", "foo_id", (c) {
        c.deleteRule = DeleteRule.cascade;
      });
      expect(builder.commands.length, 4);
      expect(builder.commands.last,
          "database.alterColumn(\"bar\", \"foo_id\", (c) {c.deleteRule = DeleteRule.cascade;});");

      builder.alterColumn("bar", "foo_id", (c) {
        c.deleteRule = DeleteRule.cascade;
      });
      expect(builder.commands.length, 4);
    });

    test("Multiple statements", () {
      builder.createTable(SchemaTable("foo", [
        SchemaColumn("id", ManagedPropertyType.integer,
            isIndexed: false, isUnique: false)
      ]));
      builder.alterColumn("foo", "id", (c) {
        c.isIndexed = true;
        c.isUnique = true;
      });
      expect(builder.commands.length, 2);
      expect(builder.commands.last,
          "database.alterColumn(\"foo\", \"id\", (c) {c.isIndexed = true;c.isUnique = true;});");
    });
  });
}
