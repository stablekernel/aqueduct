import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/runtime/orm/entity_mirrors.dart';
import 'package:test/test.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

// These tests verifying that the raw persistent store migration commands are mapped to one or more specific SQL statements
void main() {
  group("Table generation command mapping", () {
    PostgreSQLPersistentStore psc;
    setUp(() {
      psc = PostgreSQLPersistentStore(null, null, null, null, null);
    });

    test("Property tables generate appropriate postgresql commands", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);
      var commands = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(commands[0],
          "CREATE TABLE _GeneratorModel1 (id BIGSERIAL PRIMARY KEY,name TEXT NOT NULL,option BOOLEAN NOT NULL,points DOUBLE PRECISION NOT NULL UNIQUE,validDate TIMESTAMP NULL,document JSONB NOT NULL)");
      expect(commands.length, 1);
    });

    test("Create temporary table", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);
      var commands = schema.tables
          .map((t) => psc.createTable(t, isTemporary: true))
          .expand((l) => l)
          .toList();

      expect(commands[0],
          "CREATE TEMPORARY TABLE _GeneratorModel1 (id BIGSERIAL PRIMARY KEY,name TEXT NOT NULL,option BOOLEAN NOT NULL,points DOUBLE PRECISION NOT NULL UNIQUE,validDate TIMESTAMP NULL,document JSONB NOT NULL)");
      expect(commands.length, 1);
    });

    test("Create table with indices", () {
      var dm = ManagedDataModel([GeneratorModel2]);
      var schema = Schema.fromDataModel(dm);
      schema.tableForName("_GeneratorModel2").addColumn(
          SchemaColumn("a", ManagedPropertyType.integer, isIndexed: true));
      var commands = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(commands[0],
          "CREATE TABLE _GeneratorModel2 (id INT PRIMARY KEY,a INT NOT NULL)");
      expect(commands[1],
          "CREATE INDEX _GeneratorModel2_a_idx ON _GeneratorModel2 (a)");
    });

    test("Create multiple tables with trailing index", () {
      var dm = ManagedDataModel([GeneratorModel1, GeneratorModel2]);
      var schema = Schema.fromDataModel(dm);
      var commands = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(commands[0],
          "CREATE TABLE _GeneratorModel1 (id BIGSERIAL PRIMARY KEY,name TEXT NOT NULL,option BOOLEAN NOT NULL,points DOUBLE PRECISION NOT NULL UNIQUE,validDate TIMESTAMP NULL,document JSONB NOT NULL)");
      expect(commands[1], "CREATE TABLE _GeneratorModel2 (id INT PRIMARY KEY)");
    });

    test("Default values are properly serialized", () {
      var dm = ManagedDataModel([GeneratorModel3]);
      var schema = Schema.fromDataModel(dm);
      var commands = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(commands[0],
          "CREATE TABLE _GeneratorModel3 (creationDate TIMESTAMP NOT NULL DEFAULT (now() at time zone 'utc'),id INT PRIMARY KEY,textValue TEXT NOT NULL DEFAULT \$\$dflt\$\$,option BOOLEAN NOT NULL DEFAULT true,otherTime TIMESTAMP NOT NULL DEFAULT '1900-01-01T00:00:00.000Z',value DOUBLE PRECISION NOT NULL DEFAULT 20.0)");
    });

    test("Table with @Table(name) overrides class name", () {
      var dm = ManagedDataModel([GenNamed]);
      var schema = Schema.fromDataModel(dm);
      var commands = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(commands, ["CREATE TABLE GenNamed (id INT PRIMARY KEY)"]);
    });

    test("One-to-one relationships are generated", () {
      var dm = ManagedDataModel([GenOwner, GenAuth]);
      var schema = Schema.fromDataModel(dm);
      var cmds = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(cmds[0], "CREATE TABLE _GenOwner (id BIGSERIAL PRIMARY KEY)");
      expect(cmds[1],
          "CREATE TABLE _GenAuth (id INT PRIMARY KEY,owner_id BIGINT NULL UNIQUE)");
      expect(
          cmds[2], "CREATE INDEX _GenAuth_owner_id_idx ON _GenAuth (owner_id)");
      expect(cmds[3],
          "ALTER TABLE ONLY _GenAuth ADD FOREIGN KEY (owner_id) REFERENCES _GenOwner (id) ON DELETE CASCADE");
      expect(cmds.length, 4);
    });

    test("One-to-many relationships are generated", () {
      var dm = ManagedDataModel([GenUser, GenPost]);
      var schema = Schema.fromDataModel(dm);
      var cmds = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(
          cmds.contains(
              "CREATE TABLE _GenUser (id INT PRIMARY KEY,name TEXT NOT NULL)"),
          true);
      expect(
          cmds.contains(
              "CREATE TABLE _GenPost (id INT PRIMARY KEY,text TEXT NOT NULL,owner_id INT NULL)"),
          true);
      expect(
          cmds.contains(
              "CREATE INDEX _GenPost_owner_id_idx ON _GenPost (owner_id)"),
          true);
      expect(
          cmds.contains(
              "ALTER TABLE ONLY _GenPost ADD FOREIGN KEY (owner_id) REFERENCES _GenUser (id) ON DELETE RESTRICT"),
          true);
      expect(cmds.length, 4);
    });

    test("Many-to-many relationships are generated", () {
      var dm = ManagedDataModel([GenLeft, GenRight, GenJoin]);
      var schema = Schema.fromDataModel(dm);
      var cmds = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(cmds.contains("CREATE TABLE _GenLeft (id INT PRIMARY KEY)"), true);
      expect(
          cmds.contains("CREATE TABLE _GenRight (id INT PRIMARY KEY)"), true);
      expect(
          cmds.contains(
              "CREATE TABLE _GenJoin (id BIGSERIAL PRIMARY KEY,left_id INT NULL,right_id INT NULL)"),
          true);
      expect(
          cmds.contains(
              "ALTER TABLE ONLY _GenJoin ADD FOREIGN KEY (left_id) REFERENCES _GenLeft (id) ON DELETE SET NULL"),
          true);
      expect(
          cmds.contains(
              "ALTER TABLE ONLY _GenJoin ADD FOREIGN KEY (right_id) REFERENCES _GenRight (id) ON DELETE SET NULL"),
          true);
      expect(
          cmds.contains(
              "CREATE INDEX _GenJoin_left_id_idx ON _GenJoin (left_id)"),
          true);
      expect(
          cmds.contains(
              "CREATE INDEX _GenJoin_right_id_idx ON _GenJoin (right_id)"),
          true);
      expect(cmds.length, 7);
    });

    test("Serial types in relationships are properly inversed", () {
      var dm = ManagedDataModel([GenOwner, GenAuth]);
      var schema = Schema.fromDataModel(dm);
      var cmds = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(
          cmds.contains(
              "CREATE TABLE _GenAuth (id INT PRIMARY KEY,owner_id BIGINT NULL UNIQUE)"),
          true);
    });

    test("Private fields are generated as columns", () {
      var dm = ManagedDataModel([PrivateField]);
      var schema = Schema.fromDataModel(dm);
      var cmds = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(
          cmds.contains(
              "CREATE TABLE _PrivateField (id BIGSERIAL PRIMARY KEY,_private TEXT NOT NULL)"),
          true);
    });

    test("Enum fields are generated as strings", () {
      var dm = ManagedDataModel([EnumObject]);
      var schema = Schema.fromDataModel(dm);
      var cmds = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(
          cmds.contains(
              "CREATE TABLE _EnumObject (id BIGSERIAL PRIMARY KEY,enumValues TEXT NOT NULL)"),
          true);
    });

    test("Create table with unique set", () {
      var dm = ManagedDataModel([Unique]);
      var schema = Schema.fromDataModel(dm);
      var cmds = schema.tables
          .map((t) => psc.createTable(t))
          .expand((l) => l)
          .toList();

      expect(cmds[0],
          "CREATE TABLE _Unique (id BIGSERIAL PRIMARY KEY,a TEXT NOT NULL,b TEXT NOT NULL,c TEXT NOT NULL)");
      expect(
          cmds[1], "CREATE UNIQUE INDEX _Unique_unique_idx ON _Unique (a,b)");
    });
  });

  group("Non-create table generator mappings", () {
    PostgreSQLPersistentStore psc;
    setUp(() {
      psc = PostgreSQLPersistentStore(null, null, null, null, null);
    });

    test("Delete table", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);
      var cmds = psc.deleteTable(schema.tableForName("_GeneratorModel1"));
      expect(cmds, ["DROP TABLE _GeneratorModel1"]);
    });

    test("Add simple column", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);

      var propDesc = ManagedAttributeDescription(
          dm.entityForType(GeneratorModel1),
          "foobar",
          getManagedTypeFromType(reflectType(int)),
          null,
          nullable: true);
      var cmds = psc.addColumn(
          schema.tables.first, SchemaColumn.fromProperty(propDesc));
      expect(cmds, ["ALTER TABLE _GeneratorModel1 ADD COLUMN foobar INT NULL"]);
    });

    test("Add column with index", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);

      var propDesc = ManagedAttributeDescription(
          dm.entityForType(GeneratorModel1),
          "foobar",
          getManagedTypeFromType(reflectType(int)),
          null,
          defaultValue: "4",
          unique: true,
          indexed: true,
          nullable: true,
          autoincrement: true);
      var cmds = psc.addColumn(
          schema.tables.first, SchemaColumn.fromProperty(propDesc));
      expect(cmds.first,
          "ALTER TABLE _GeneratorModel1 ADD COLUMN foobar SERIAL NULL DEFAULT 4 UNIQUE");
      expect(cmds.last,
          "CREATE INDEX _GeneratorModel1_foobar_idx ON _GeneratorModel1 (foobar)");
    });

    test("Add foreign key column (index + constraint)", () {
      var dm = ManagedDataModel([GeneratorModel1, GeneratorModel2]);
      var schema = Schema.fromDataModel(dm);

      var propDesc = ManagedRelationshipDescription(
          dm.entityForType(GeneratorModel1),
          "foobar",
          getManagedTypeFromType(reflectType(String)),
          null,
          dm.entityForType(GeneratorModel2),
          DeleteRule.cascade,
          ManagedRelationshipType.belongsTo,
          dm.entityForType(GeneratorModel2).primaryKey,
          indexed: true,
          nullable: true);
      var cmds = psc.addColumn(
          schema.tables.first, SchemaColumn.fromProperty(propDesc));
      expect(cmds[0],
          "ALTER TABLE _GeneratorModel1 ADD COLUMN foobar_id TEXT NULL");
      expect(cmds[1],
          "CREATE INDEX _GeneratorModel1_foobar_id_idx ON _GeneratorModel1 (foobar_id)");
      expect(cmds[2],
          "ALTER TABLE ONLY _GeneratorModel1 ADD FOREIGN KEY (foobar_id) REFERENCES _GeneratorModel2 (id) ON DELETE CASCADE");
    });

    test("Delete column", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);
      var cmds = psc.deleteColumn(schema.tables.first,
          schema.tables.first.columns.firstWhere((s) => s.name == "validDate"));
      expect(cmds.first,
          "ALTER TABLE _GeneratorModel1 DROP COLUMN validDate RESTRICT");
    });

    test("Delete foreign key column", () {
      var dm = ManagedDataModel([GenUser, GenPost]);
      var schema = Schema.fromDataModel(dm);
      var cmds = psc.deleteColumn(schema.tables.last,
          schema.tables.last.columns.firstWhere((c) => c.name == "owner"));
      expect(cmds.first, "ALTER TABLE _GenPost DROP COLUMN owner_id CASCADE");
    });

    test("Add index to column", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);
      var cmds = psc.addIndexToColumn(schema.tables.first,
          schema.tables.first.columns.firstWhere((s) => s.name == "validDate"));
      expect(cmds.first,
          "CREATE INDEX _GeneratorModel1_validDate_idx ON _GeneratorModel1 (validDate)");
    });

    test("Remove index from column", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);
      var cmds = psc.deleteIndexFromColumn(schema.tables.first,
          schema.tables.first.columns.firstWhere((s) => s.name == "validDate"));
      expect(cmds.first, "DROP INDEX _GeneratorModel1_validDate_idx");
    });

    test("Alter column change nullabiity", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);
      var originalColumn =
          schema.tables.first.columns.firstWhere((sc) => sc.name == "name");
      expect(originalColumn.isNullable, false);

      var col = SchemaColumn.from(originalColumn);

      // Add nullability
      col.isNullable = true;
      var cmds = psc.alterColumnNullability(schema.tables.first, col, null);
      expect(cmds.first,
          "ALTER TABLE _GeneratorModel1 ALTER COLUMN name DROP NOT NULL");

      // Remove nullability, but don't provide value to update things to:
      col.isNullable = false;
      cmds = psc.alterColumnNullability(schema.tables.first, col, "'foo'");
      expect(cmds, [
        "UPDATE _GeneratorModel1 SET name='foo' WHERE name IS NULL",
        "ALTER TABLE _GeneratorModel1 ALTER COLUMN name SET NOT NULL",
      ]);
    });

    test("Alter column change uniqueness", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);
      var originalColumn =
          schema.tables.first.columns.firstWhere((sc) => sc.name == "name");
      expect(originalColumn.isUnique, false);

      var col = SchemaColumn.from(originalColumn);

      // Add unique
      col.isUnique = true;
      var cmds = psc.alterColumnUniqueness(schema.tables.first, col);
      expect(cmds.first, "ALTER TABLE _GeneratorModel1 ADD UNIQUE (name)");

      // Remove unique
      col.isUnique = false;
      cmds = psc.alterColumnUniqueness(schema.tables.first, col);
      expect(cmds.first,
          "ALTER TABLE _GeneratorModel1 DROP CONSTRAINT _GeneratorModel1_name_key");
    });

    test("Alter column change default value", () {
      var dm = ManagedDataModel([GeneratorModel1]);
      var schema = Schema.fromDataModel(dm);
      var originalColumn =
          schema.tables.first.columns.firstWhere((sc) => sc.name == "name");
      expect(originalColumn.defaultValue, isNull);

      var col = SchemaColumn.from(originalColumn);

      // Add default
      col.defaultValue = "'foobar'";
      var cmds = psc.alterColumnDefaultValue(schema.tables.first, col);
      expect(cmds.first,
          "ALTER TABLE _GeneratorModel1 ALTER COLUMN name SET DEFAULT 'foobar'");

      // Remove default
      col.defaultValue = null;
      cmds = psc.alterColumnDefaultValue(schema.tables.first, col);
      expect(cmds.first,
          "ALTER TABLE _GeneratorModel1 ALTER COLUMN name DROP DEFAULT");
    });

    test("Alter column change delete rule", () {
      var dm = ManagedDataModel([GenUser, GenPost]);
      var schema = Schema.fromDataModel(dm);
      var postTable = schema.tables.firstWhere((t) => t.name == "_GenPost");
      var originalColumn =
          postTable.columns.firstWhere((sc) => sc.name == "owner");
      expect(originalColumn.deleteRule, DeleteRule.restrict);

      var col = SchemaColumn.from(originalColumn);

      // Change delete rule
      col.deleteRule = DeleteRule.nullify;
      var cmds = psc.alterColumnDeleteRule(postTable, col);
      expect(cmds.first,
          "ALTER TABLE ONLY _GenPost DROP CONSTRAINT _GenPost_owner_id_fkey");
      expect(cmds.last,
          "ALTER TABLE ONLY _GenPost ADD FOREIGN KEY (owner_id) REFERENCES _GenUser (id) ON DELETE SET NULL");
    });
  });

  group("Unique column set", () {
    PostgreSQLPersistentStore psc;
    setUp(() {
      psc = PostgreSQLPersistentStore(null, null, null, null, null);
    });

    test("Can add unique", () {
      var dm = ManagedDataModel([Unique]);
      var schema = Schema.fromDataModel(dm);

      var cmds = psc.addTableUniqueColumnSet(schema.tableForName("_Unique"));
      expect(cmds.first,
          "CREATE UNIQUE INDEX _Unique_unique_idx ON _Unique (a,b)");
    });

    test("Can remove unique", () {
      var dm = ManagedDataModel([Unique]);
      var schema = Schema.fromDataModel(dm);
      schema.tableForName("_Unique").uniqueColumnSet = null;

      var cmds = psc.deleteTableUniqueColumnSet(schema.tableForName("_Unique"));
      expect(cmds.first, "DROP INDEX IF EXISTS _Unique_unique_idx");
    });

    test("Can use foreign key", () {
      var dm = ManagedDataModel([UniqueContainer, UniqueBelongsTo]);
      var schema = Schema.fromDataModel(dm);

      var cmds =
          psc.addTableUniqueColumnSet(schema.tableForName("_UniqueBelongsTo"));
      expect(cmds.first,
          "CREATE UNIQUE INDEX _UniqueBelongsTo_unique_idx ON _UniqueBelongsTo (a,container_id)");
    });
  });
}

class GeneratorModel1 extends ManagedObject<_GeneratorModel1>
    implements _GeneratorModel1 {
  @Serialize()
  String foo;
}

class _GeneratorModel1 {
  @primaryKey
  int id;

  String name;

  bool option;

  @Column(unique: true)
  double points;

  @Column(nullable: true)
  DateTime validDate;

  Document document;
}

class GeneratorModel2 extends ManagedObject<_GeneratorModel2>
    implements _GeneratorModel2 {}

class _GeneratorModel2 {
  @Column(primaryKey: true, indexed: true)
  int id;
}

class GeneratorModel3 extends ManagedObject<_GeneratorModel3>
    implements _GeneratorModel3 {}

class _GeneratorModel3 {
  @Column(defaultValue: "(now() at time zone 'utc')")
  DateTime creationDate;

  @Column(primaryKey: true, defaultValue: "18")
  int id;

  @Column(defaultValue: "\$\$dflt\$\$")
  String textValue;

  @Column(defaultValue: "true")
  bool option;

  @Column(defaultValue: "'1900-01-01T00:00:00.000Z'")
  DateTime otherTime;

  @Column(defaultValue: "20.0")
  double value;
}

class GenUser extends ManagedObject<_GenUser> implements _GenUser {}

class _GenUser {
  @Column(primaryKey: true)
  int id;

  String name;

  ManagedSet<GenPost> posts;
}

class GenPost extends ManagedObject<_GenPost> implements _GenPost {}

class _GenPost {
  @Column(primaryKey: true)
  int id;

  String text;

  @Relate(Symbol('posts'), isRequired: false, onDelete: DeleteRule.restrict)
  GenUser owner;
}

class GenNamed extends ManagedObject<_GenNamed> implements _GenNamed {}

@Table(name: "GenNamed")
class _GenNamed {
  @Column(primaryKey: true)
  int id;
}

class GenOwner extends ManagedObject<_GenOwner> implements _GenOwner {}

class _GenOwner {
  @primaryKey
  int id;

  GenAuth auth;
}

class GenAuth extends ManagedObject<_GenAuth> implements _GenAuth {}

class _GenAuth {
  @Column(primaryKey: true)
  int id;

  @Relate(Symbol('auth'), isRequired: false, onDelete: DeleteRule.cascade)
  GenOwner owner;
}

class GenLeft extends ManagedObject<_GenLeft> implements _GenLeft {}

class _GenLeft {
  @Column(primaryKey: true)
  int id;

  ManagedSet<GenJoin> join;
}

class GenRight extends ManagedObject<_GenRight> implements _GenRight {}

class _GenRight {
  @Column(primaryKey: true)
  int id;

  ManagedSet<GenJoin> join;
}

class GenJoin extends ManagedObject<_GenJoin> implements _GenJoin {}

class _GenJoin {
  @primaryKey
  int id;

  @Relate(Symbol('join'))
  GenLeft left;

  @Relate(Symbol('join'))
  GenRight right;
}

class GenObj extends ManagedObject<_GenObj> implements _GenObj {}

class _GenObj {
  @primaryKey
  int id;

  GenNotNullable gen;
}

class GenNotNullable extends ManagedObject<_GenNotNullable>
    implements _GenNotNullable {}

class _GenNotNullable {
  @primaryKey
  int id;

  @Relate(Symbol('gen'), onDelete: DeleteRule.nullify, isRequired: false)
  GenObj ref;
}

class PrivateField extends ManagedObject<_PrivateField>
    implements _PrivateField {
  set public(String p) {
    _private = p;
  }

  String get public => _private;
}

class _PrivateField {
  @primaryKey
  int id;

  String _private;
}

enum EnumValues { abcd, efgh, other18 }

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}

class _EnumObject {
  @primaryKey
  int id;

  EnumValues enumValues;
}

class Unique extends ManagedObject<_Unique> {}

@Table.unique([Symbol('a'), Symbol('b')])
class _Unique {
  @primaryKey
  int id;

  String a;
  String b;
  String c;
}

class UniqueContainer extends ManagedObject<_UniqueContainer> {}

class _UniqueContainer {
  @primaryKey
  int id;

  UniqueBelongsTo contains;
}

class UniqueBelongsTo extends ManagedObject<_UniqueBelongsTo> {}

@Table.unique([Symbol('a'), Symbol('container')])
class _UniqueBelongsTo {
  @primaryKey
  int id;

  int a;
  @Relate(Symbol('contains'))
  UniqueContainer container;
}
