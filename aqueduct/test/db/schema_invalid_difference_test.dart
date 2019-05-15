import 'package:aqueduct/src/db/db.dart';
import 'package:test/test.dart';

void main() {
  test("Cannot change type", () {
    final original = Schema([
      SchemaTable(
          "_u", [SchemaColumn("id", ManagedType.integer, isPrimaryKey: true)]),
    ]);

    final dest = Schema.from(original)
      ..tableForName("_u").columnForName("id").type =
          ManagedPropertyType.doublePrecision;

    try {
      SchemaDifference(original, dest);
      fail('unreachable');
    } on SchemaException catch (e) {
      expect(e.toString(), contains("Cannot change type of '_u.id'"));
    }
  });

  test("Cannot change relatedTable", () {
    final original = Schema([
      SchemaTable(
          "_u", [SchemaColumn("id", ManagedType.integer, isPrimaryKey: true)]),
      SchemaTable("_t", [
        SchemaColumn("id", ManagedType.integer, isPrimaryKey: true),
        SchemaColumn.relationship("_u_id", ManagedType.integer,
            relatedTableName: "_u", relatedColumnName: "id")
      ])
    ]);

    final dest = Schema.from(original)
      ..addTable(SchemaTable(
          "_v", [SchemaColumn("id", ManagedType.integer, isPrimaryKey: true)]))
      ..tableForName("_t").columnForName("_u_id").relatedTableName = "_v";

    try {
      SchemaDifference(original, dest);
      fail('unreachable');
    } on SchemaException catch (e) {
      expect(e.toString(), contains("Cannot change type of '_t._u_id'"));
    }
  });

  test("Cannot change primary key property", () {
    final original = Schema([
      SchemaTable(
          "_u", [SchemaColumn("id", ManagedType.integer, isPrimaryKey: true)]),
    ]);

    final dest = Schema.from(original)
      ..tableForName("_u").addColumn(SchemaColumn(
          "replacement", ManagedPropertyType.integer,
          isPrimaryKey: true))
      ..tableForName("_u").columnForName("id").isPrimaryKey = false;

    try {
      SchemaDifference(original, dest);
      fail('unreachable');
    } on SchemaException catch (e) {
      expect(e.toString(), contains("Cannot change primary key of '_u'"));
    }
  });

  test("Cannot change autoincrementing", () {
    final original = Schema([
      SchemaTable("_u", [
        SchemaColumn("id", ManagedType.integer, isPrimaryKey: true),
        SchemaColumn("auto", ManagedType.integer, autoincrement: true),
        SchemaColumn("not_auto", ManagedType.integer, autoincrement: false),
      ]),
    ]);

    try {
      SchemaDifference(
          original,
          Schema.from(original)
            ..tableForName("_u").columnForName("auto").autoincrement = false);
      fail('unreachable');
    } on SchemaException catch (e) {
      expect(e.toString(),
          contains("Cannot change autoincrement behavior of '_u.auto'"));
    }

    try {
      SchemaDifference(
          original,
          Schema.from(original)
            ..tableForName("_u").columnForName("not_auto").autoincrement =
                true);
      fail('unreachable');
    } on SchemaException catch (e) {
      expect(e.toString(),
          contains("Cannot change autoincrement behavior of '_u.not_auto'"));
    }
  });

  test("Cannot change autoincrementing", () {
    final original = Schema([
      SchemaTable("_u", [
        SchemaColumn("id", ManagedType.integer, isPrimaryKey: true),
        SchemaColumn("i", ManagedType.integer, autoincrement: true)
      ]),
    ]);

    try {
      SchemaDifference(
          original,
          Schema.from(original)
            ..tableForName("_u").columnForName("i").type =
                ManagedPropertyType.string);
      fail('unreachable');
    } on SchemaException catch (e) {
      expect(e.toString(), contains("Cannot change type of '_u.i'"));
    }
  });
}
