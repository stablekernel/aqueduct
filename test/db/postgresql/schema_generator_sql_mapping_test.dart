import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  group("Table generation command mapping", () {
    PostgreSQLPersistentStore psc;
    setUp(() {
      psc = new PostgreSQLPersistentStore(() => null);
    });

    test("Property tables generate appropriate postgresql commands", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);
      var commands = schema.tables.map((t) => psc.createTable(t)).expand((l) => l).toList();

      expect(commands[0], "CREATE TABLE _GeneratorModel1 (id BIGSERIAL PRIMARY KEY,name TEXT NOT NULL,option BOOLEAN NOT NULL,points DOUBLE PRECISION NOT NULL UNIQUE,validDate TIMESTAMP NULL)");
    });

    test("Create temporary table", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);
      var commands = schema.tables.map((t) => psc.createTable(t, isTemporary: true)).expand((l) => l).toList();

      expect(commands[0], "CREATE TEMPORARY TABLE _GeneratorModel1 (id BIGSERIAL PRIMARY KEY,name TEXT NOT NULL,option BOOLEAN NOT NULL,points DOUBLE PRECISION NOT NULL UNIQUE,validDate TIMESTAMP NULL)");
    });

    test("Create table with indices", () {
      var dm = new DataModel([GeneratorModel2]);
      var schema = new Schema.fromDataModel(dm);
      var commands = schema.tables.map((t) => psc.createTable(t)).expand((l) => l).toList();

      expect(commands[0], "CREATE TABLE _GeneratorModel2 (id INT PRIMARY KEY)");
      expect(commands[1], "CREATE INDEX _GeneratorModel2_id_idx ON _GeneratorModel2 (id)");
    });

    test("Create multiple tables with trailing index", () {
      var dm = new DataModel([GeneratorModel1, GeneratorModel2]);
      var schema = new Schema.fromDataModel(dm);
      var commands = schema.tables.map((t) => psc.createTable(t)).expand((l) => l).toList();

      expect(commands[0], "CREATE TABLE _GeneratorModel1 (id BIGSERIAL PRIMARY KEY,name TEXT NOT NULL,option BOOLEAN NOT NULL,points DOUBLE PRECISION NOT NULL UNIQUE,validDate TIMESTAMP NULL)");
      expect(commands[1], "CREATE TABLE _GeneratorModel2 (id INT PRIMARY KEY)");
      expect(commands[2], "CREATE INDEX _GeneratorModel2_id_idx ON _GeneratorModel2 (id)");
    });

    test("Default values are properly serialized", () {
      var dm = new DataModel([GeneratorModel3]);
      var schema = new Schema.fromDataModel(dm);
      var commands = schema.tables.map((t) => psc.createTable(t)).expand((l) => l).toList();

      expect(commands[0], "CREATE TABLE _GeneratorModel3 (creationDate TIMESTAMP NOT NULL DEFAULT (now() at time zone 'utc'),id INT PRIMARY KEY,textValue TEXT NOT NULL DEFAULT \$\$dflt\$\$,option BOOLEAN NOT NULL DEFAULT true,otherTime TIMESTAMP NOT NULL DEFAULT '1900-01-01T00:00:00.000Z',value DOUBLE PRECISION NOT NULL DEFAULT 20.0)");
    });

    test("Table with tableName() overrides class name", () {
      var dm = new DataModel([GenNamed]);
      var schema = new Schema.fromDataModel(dm);
      var commands = schema.tables.map((t) => psc.createTable(t)).expand((l) => l).toList();

      expect(commands, ["CREATE TABLE GenNamed (id INT PRIMARY KEY)"]);
    });

    test("One-to-one relationships are generated", () {
      var dm = new DataModel([GenOwner, GenAuth]);
      var schema = new Schema.fromDataModel(dm);
      var cmds = schema.tables.map((t) => psc.createTable(t)).expand((l) => l).toList();

      expect(cmds[0], "CREATE TABLE _GenOwner (id BIGSERIAL PRIMARY KEY)");
      expect(cmds[1], "CREATE TABLE _GenAuth (id INT PRIMARY KEY,owner_id BIGINT NULL UNIQUE)");
      expect(cmds[2], "CREATE INDEX _GenAuth_owner_id_idx ON _GenAuth (owner_id)");
      expect(cmds[3], "ALTER TABLE ONLY _GenAuth ADD FOREIGN KEY (owner_id) REFERENCES _GenOwner (id) ON DELETE CASCADE");
      expect(cmds.length, 4);
    });

    test("One-to-many relationships are generated", () {
      var dm = new DataModel([GenUser, GenPost]);
      var schema = new Schema.fromDataModel(dm);
      var cmds = schema.tables.map((t) => psc.createTable(t)).expand((l) => l).toList();

      expect(cmds.contains("CREATE TABLE _GenUser (id INT PRIMARY KEY,name TEXT NOT NULL)"), true);
      expect(cmds.contains("CREATE TABLE _GenPost (id INT PRIMARY KEY,text TEXT NOT NULL,owner_id INT NULL)"), true);
      expect(cmds.contains("CREATE INDEX _GenPost_owner_id_idx ON _GenPost (owner_id)"), true);
      expect(cmds.contains("ALTER TABLE ONLY _GenPost ADD FOREIGN KEY (owner_id) REFERENCES _GenUser (id) ON DELETE RESTRICT"), true);
      expect(cmds.length, 4);
    });

    test("Many-to-many relationships are generated", () {
      var dm = new DataModel([GenLeft, GenRight, GenJoin]);
      var schema = new Schema.fromDataModel(dm);
      var cmds = schema.tables.map((t) => psc.createTable(t)).expand((l) => l).toList();

      expect(cmds.contains("CREATE TABLE _GenLeft (id INT PRIMARY KEY)"), true);
      expect(cmds.contains("CREATE TABLE _GenRight (id INT PRIMARY KEY)"), true);
      expect(cmds.contains("CREATE TABLE _GenJoin (id BIGSERIAL PRIMARY KEY,left_id INT NULL,right_id INT NULL)"), true);
      expect(cmds.contains("ALTER TABLE ONLY _GenJoin ADD FOREIGN KEY (left_id) REFERENCES _GenLeft (id) ON DELETE SET NULL"), true);
      expect(cmds.contains("ALTER TABLE ONLY _GenJoin ADD FOREIGN KEY (right_id) REFERENCES _GenRight (id) ON DELETE SET NULL"), true);
      expect(cmds.contains("CREATE INDEX _GenJoin_left_id_idx ON _GenJoin (left_id)"), true);
      expect(cmds.contains("CREATE INDEX _GenJoin_right_id_idx ON _GenJoin (right_id)"), true);
      expect(cmds.length, 7);
    });

    test("Serial types in relationships are properly inversed", () {
      var dm = new DataModel([GenOwner, GenAuth]);
      var schema = new Schema.fromDataModel(dm);
      var cmds = schema.tables.map((t) => psc.createTable(t)).expand((l) => l).toList();

      expect(cmds.contains("CREATE TABLE _GenAuth (id INT PRIMARY KEY,owner_id BIGINT NULL UNIQUE)"), true);
    });
  });

  group("Non-create table generator mappings", () {
    PostgreSQLPersistentStore psc;
    setUp(() {
      psc = new PostgreSQLPersistentStore(() => null);
    });

    test("Delete table", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);
      var cmds = psc.deleteTable(schema.tableForName("_GeneratorModel1"));
      expect(cmds, ["DROP TABLE _GeneratorModel1"]);
    });

    test("Add simple column", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);

      var propDesc = new AttributeDescription(dm.entityForType(GeneratorModel1), "foobar", PropertyType.integer);
      var cmds = psc.addColumn(schema.tables.first, new SchemaColumn.fromEntity(dm.entityForType(GeneratorModel1), propDesc));
      expect(cmds, ["ALTER TABLE _GeneratorModel1 ADD COLUMN foobar INT NOT NULL"]);
    });

    test("Add column with index", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);

      var propDesc = new AttributeDescription(dm.entityForType(GeneratorModel1), "foobar", PropertyType.integer, defaultValue: "4", unique: true, indexed: true, nullable: true, autoincrement: true);
      var cmds = psc.addColumn(schema.tables.first, new SchemaColumn.fromEntity(dm.entityForType(GeneratorModel1), propDesc));
      expect(cmds.first, "ALTER TABLE _GeneratorModel1 ADD COLUMN foobar SERIAL NULL DEFAULT 4 UNIQUE");
      expect(cmds.last, "CREATE INDEX _GeneratorModel1_foobar_idx ON _GeneratorModel1 (foobar)");
    });

    test("Add foreign key column (index + constraint)", () {
      var dm = new DataModel([GeneratorModel1, GeneratorModel2]);
      var schema = new Schema.fromDataModel(dm);

      var propDesc = new RelationshipDescription(dm.entityForType(GeneratorModel1), "foobar", PropertyType.string, dm.entityForType(GeneratorModel2),
        RelationshipDeleteRule.cascade, RelationshipType.belongsTo, new Symbol(dm.entityForType(GeneratorModel2).primaryKey), indexed: true);
      var cmds = psc.addColumn(schema.tables.first, new SchemaColumn.fromEntity(dm.entityForType(GeneratorModel1), propDesc));
      expect(cmds[0], "ALTER TABLE _GeneratorModel1 ADD COLUMN foobar_id TEXT NOT NULL");
      expect(cmds[1], "CREATE INDEX _GeneratorModel1_foobar_id_idx ON _GeneratorModel1 (foobar_id)");
      expect(cmds[2], "ALTER TABLE ONLY _GeneratorModel1 ADD FOREIGN KEY (foobar_id) REFERENCES _GeneratorModel2 (id) ON DELETE CASCADE");
    });

    test("Delete column", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);
      var cmds = psc.deleteColumn(schema.tables.first, schema.tables.first.columns.last);
      expect(cmds.first, "ALTER TABLE _GeneratorModel1 DROP COLUMN validDate RESTRICT");
    });

    test("Delete foreign key column", () {
      var dm = new DataModel([GenUser, GenPost]);
      var schema = new Schema.fromDataModel(dm);
      var cmds = psc.deleteColumn(schema.tables.last, schema.tables.last.columns.firstWhere((c) => c.name == "owner"));
      expect(cmds.first, "ALTER TABLE _GenPost DROP COLUMN owner_id CASCADE");
    });

    test("Add index to column", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);
      var cmds = psc.addIndexToColumn(schema.tables.first, schema.tables.first.columns.last);
      expect(cmds.first, "CREATE INDEX _GeneratorModel1_validDate_idx ON _GeneratorModel1 (validDate)");
    });

    test("Remove index from column", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);
      var cmds = psc.deleteIndexFromColumn(schema.tables.first, schema.tables.first.columns.last);
      expect(cmds.first, "DROP INDEX _GeneratorModel1_validDate_idx");
    });

    test("Alter column change nullabiity", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);
      var originalColumn = schema.tables.first.columns.firstWhere((sc) => sc.name == "name");
      expect(originalColumn.isNullable, false);

      var col = new SchemaColumn.from(originalColumn);

      // Add nullability
      col.isNullable = true;
      var cmds = psc.alterColumnNullability(schema.tables.first, col, null);
      expect(cmds.first, "ALTER TABLE _GeneratorModel1 ALTER COLUMN name DROP NOT NULL");

      // Remove nullability, but don't provide value to update things to:
      col.isNullable = false;
      try {
        cmds = psc.alterColumnNullability(schema.tables.first, col, null);
        expect(true, false);
      } on SchemaException {}

      cmds = psc.alterColumnNullability(schema.tables.first, col, "'foo'");
      expect(cmds.first, "UPDATE _GeneratorModel1 SET name='foo' WHERE name IS NULL");
      expect(cmds.last, "ALTER TABLE _GeneratorModel1 ALTER COLUMN name SET NOT NULL");
    });

    test("Alter column change uniqueness", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);
      var originalColumn = schema.tables.first.columns.firstWhere((sc) => sc.name == "name");
      expect(originalColumn.isUnique, false);

      var col = new SchemaColumn.from(originalColumn);

      // Add unique
      col.isUnique = true;
      var cmds = psc.alterColumnUniqueness(schema.tables.first, col);
      expect(cmds.first, "ALTER TABLE _GeneratorModel1 ADD UNIQUE (name)");

      // Remove unique
      col.isUnique = false;
      cmds = psc.alterColumnUniqueness(schema.tables.first, col);
      expect(cmds.first, "ALTER TABLE _GeneratorModel1 DROP CONSTRAINT _GeneratorModel1_name_key");
    });

    test("Alter column change default value", () {
      var dm = new DataModel([GeneratorModel1]);
      var schema = new Schema.fromDataModel(dm);
      var originalColumn = schema.tables.first.columns.firstWhere((sc) => sc.name == "name");
      expect(originalColumn.defaultValue, isNull);

      var col = new SchemaColumn.from(originalColumn);

      // Add default
      col.defaultValue = "'foobar'";
      var cmds = psc.alterColumnDefaultValue(schema.tables.first, col);
      expect(cmds.first, "ALTER TABLE _GeneratorModel1 ALTER COLUMN name SET DEFAULT 'foobar'");

      // Remove default
      col.defaultValue = null;
      cmds = psc.alterColumnDefaultValue(schema.tables.first, col);
      expect(cmds.first, "ALTER TABLE _GeneratorModel1 ALTER COLUMN name DROP DEFAULT");
    });

    test("Alter column change delete rule", () {
      var dm = new DataModel([GenUser, GenPost]);
      var schema = new Schema.fromDataModel(dm);
      var postTable = schema.tables.firstWhere((t) => t.name == "_GenPost");
      var originalColumn = postTable.columns.firstWhere((sc) => sc.name == "owner");
      expect(originalColumn.deleteRule, RelationshipDeleteRule.restrict);

      var col = new SchemaColumn.from(originalColumn);

      // Change delete rule
      col.deleteRule = RelationshipDeleteRule.nullify;
      var cmds = psc.alterColumnDeleteRule(postTable, col);
      expect(cmds.first, "ALTER TABLE ONLY _GenPost DROP CONSTRAINT _GenPost_owner_id_fkey");
      expect(cmds.last, "ALTER TABLE ONLY _GenPost ADD FOREIGN KEY (owner_id) REFERENCES _GenUser (id) ON DELETE SET NULL");
    });
  });
}

class GeneratorModel1 extends Model<_GeneratorModel1> implements _GeneratorModel1 {
  @transientAttribute
  String foo;
}

class _GeneratorModel1 {
  @primaryKey
  int id;

  String name;

  bool option;

  @ColumnAttributes(unique: true)
  double points;

  @ColumnAttributes(nullable: true)
  DateTime validDate;
}

class GeneratorModel2 extends Model<_GeneratorModel2> implements _GeneratorModel2 {}
class _GeneratorModel2 {
  @ColumnAttributes(primaryKey: true, indexed: true)
  int id;
}

class GeneratorModel3 extends Model<_GeneratorModel3> implements _GeneratorModel3 {}
class _GeneratorModel3 {
  @ColumnAttributes(defaultValue: "(now() at time zone 'utc')")
  DateTime creationDate;

  @ColumnAttributes(primaryKey: true, defaultValue: "18")
  int id;

  @ColumnAttributes(defaultValue: "\$\$dflt\$\$")
  String textValue;

  @ColumnAttributes(defaultValue: "true")
  bool option;

  @ColumnAttributes(defaultValue: "'1900-01-01T00:00:00.000Z'")
  DateTime otherTime;

  @ColumnAttributes(defaultValue: "20.0")
  double value;
}

class GenUser extends Model<_GenUser> implements _GenUser {}

class _GenUser {
  @ColumnAttributes(primaryKey: true)
  int id;

  String name;

  OrderedSet<GenPost> posts;
}

class GenPost extends Model<_GenPost> implements _GenPost {}
class _GenPost {
  @ColumnAttributes(primaryKey: true)
  int id;

  String text;

  @RelationshipInverse(#posts, isRequired: false, onDelete: RelationshipDeleteRule.restrict)
  GenUser owner;
}

class GenNamed extends Model<_GenNamed> implements _GenNamed {}

class _GenNamed {
  @ColumnAttributes(primaryKey: true)
  int id;

  static String tableName() {
    return "GenNamed";
  }
}

class GenOwner extends Model<_GenOwner> implements _GenOwner {}
class _GenOwner {
  @primaryKey
  int id;

  GenAuth auth;
}

class GenAuth extends Model<_GenAuth> implements _GenAuth {}
class _GenAuth {
  @ColumnAttributes(primaryKey: true)
  int id;

  @RelationshipInverse(#auth, isRequired: false, onDelete: RelationshipDeleteRule.cascade)
  GenOwner owner;
}

class GenLeft extends Model<_GenLeft> implements _GenLeft {}
class _GenLeft {
  @ColumnAttributes(primaryKey: true)
  int id;

  OrderedSet<GenJoin> join;
}

class GenRight extends Model<_GenRight> implements _GenRight {}
class _GenRight {
  @ColumnAttributes(primaryKey: true)
  int id;

  OrderedSet<GenJoin> join;
}

class GenJoin extends Model<_GenJoin> implements _GenJoin {}
class _GenJoin {
  @primaryKey
  int id;

  @RelationshipInverse(#join)
  GenLeft left;

  @RelationshipInverse(#join)
  GenRight right;
}

class GenObj extends Model<_GenObj> implements _GenObj {}
class _GenObj {
  @primaryKey
  int id;

  GenNotNullable gen;
}

class GenNotNullable extends Model<_GenNotNullable> implements _GenNotNullable {}
class _GenNotNullable {
  @primaryKey
  int id;

  @RelationshipInverse(#gen, onDelete: RelationshipDeleteRule.nullify, isRequired: false)
  GenObj ref;
}
