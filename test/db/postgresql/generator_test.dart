import 'package:monadart/monadart.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {});

  tearDown(() {});

  test("Property tables generate appropriate postgresql commands", () {
    var cmd = new PostgresqlSchema.fromModels([GeneratorModel1]).toString();

    expect(cmd,
        "create table _GeneratorModel1 (id bigserial primary key,name text not null,option boolean not null,points double precision not null unique,validDate timestamp null);\n");
  });

  test("Create temporary table", () {
    var cmd = new PostgresqlSchema.fromModels([GeneratorModel1],
        temporary: true).toString();
    expect(cmd,
        "create temporary table _GeneratorModel1 (id bigserial primary key,name text not null,option boolean not null,points double precision not null unique,validDate timestamp null);\n");
  });

  test("Create table with indices", () {
    var cmd = new PostgresqlSchema.fromModels([GeneratorModel2]).toString();

    expect(cmd,
        "create table _GeneratorModel2 (id int not null);\ncreate index _GeneratorModel2_id_idx on _GeneratorModel2 (id);\n");
  });

  test("Create multiple tables with trailing index", () {
    var cmd =
        new PostgresqlSchema.fromModels([GeneratorModel1, GeneratorModel2])
            .toString();

    expect(cmd,
        "create table _GeneratorModel1 (id bigserial primary key,name text not null,option boolean not null,points double precision not null unique,validDate timestamp null);\ncreate table _GeneratorModel2 (id int not null);\ncreate index _GeneratorModel2_id_idx on _GeneratorModel2 (id);\n");
  });

  test("Default values are properly serialized", () {
    var cmd = new PostgresqlSchema.fromModels([GeneratorModel3]).toString();
    expect(cmd,
        "create table _GeneratorModel3 (creationDate timestamp not null default (now() at time zone 'utc'),id int not null default 18,option boolean not null default true,otherTime timestamp not null default '1900-01-01T00:00:00.000Z',textValue text not null default \$\$dflt\$\$,value double precision not null default 20.0);\n");
  });

  test("Table with tableName() overrides class name", () {
    var cmd = new PostgresqlSchema.fromModels([GenNamed]).toString();
    expect(cmd, "create table GenNamed (id int primary key);\n");
  });

  test("One-to-one relationships are generated", () {
    var schema = new PostgresqlSchema.fromModels([GenOwner, GenAuth]);

    var cmds = schema.schemaDefinition();

    expect(
        cmds.contains("create table _GenOwner (id bigserial primary key)"), true,
        reason: "GenOwner");
    expect(
        cmds.contains(
            "create table _GenAuth (id int primary key,owner_id bigint null unique)"),
        true,
        reason: "GenAuth");
    expect(cmds.contains("create index _GenAuth_owner_id_idx on _GenAuth (owner_id)"), true);

    expect(
        cmds.contains(
            "alter table only _GenAuth add foreign key (owner_id) references _GenOwner (id) on delete set null"),
        true,
        reason: "Alter");
    expect(cmds.length, 4);
  });

  test("One-to-many relationships are generated", () {
    var schema = new PostgresqlSchema.fromModels([GenUser, GenPost]);
    var cmds = schema.schemaDefinition();

    expect(
        cmds.contains(
            "create table _GenUser (id int primary key,name text not null)"),
        true,
        reason: "GenUser table");
    expect(
        cmds.contains(
            "create table _GenPost (id int primary key,owner_id int null,text text not null)"),
        true,
        reason: "GenPost table");
    expect(
        cmds.contains(
            "create index _GenPost_owner_id_idx on _GenPost (owner_id)"),
        true,
        reason: "GenPost index");
    expect(
        cmds.contains(
            "alter table only _GenPost add foreign key (owner_id) references _GenUser (id) on delete set null"),
        true,
        reason: "Foreign key constraint");
    expect(cmds.length, 4);
  });

  test("Many-to-many relationships are generated", () {
    var schema = new PostgresqlSchema.fromModels([GenLeft, GenRight, GenJoin]);
    var cmds = schema.schemaDefinition();

    expect(cmds.contains("create table _GenLeft (id int primary key)"), true,
        reason: "GenLeft table");
    expect(cmds.contains("create table _GenRight (id int primary key)"), true,
        reason: "GenRight table");
    expect(
        cmds.contains(
            "create table _GenJoin (left_id int null,right_id int null)"),
        true,
        reason: "GenJoin table");
    expect(
        cmds.contains(
            "alter table only _GenJoin add foreign key (left_id) references _GenLeft (id) on delete set null"),
        true,
        reason: "Left constraint");
    expect(
        cmds.contains(
            "alter table only _GenJoin add foreign key (right_id) references _GenRight (id) on delete set null"),
        true,
        reason: "Right constraint");
    expect(cmds.contains("create index _GenJoin_left_id_idx on _GenJoin (left_id)"), true);
    expect(cmds.contains("create index _GenJoin_right_id_idx on _GenJoin (right_id)"), true);
    expect(cmds.length, 7);
  });

  test("Serial types in relationships are properly inversed", () {
    var schema = new PostgresqlSchema.fromModels([GenOwner, GenAuth]);
    var cmds = schema.schemaDefinition();
    expect(
        cmds.contains(
            "create table _GenAuth (id int primary key,owner_id bigint null unique)"),
        true);
  });

  test("Delete rule of setNull throws exception if property is not nullable",
      () {
    try {
      var schema = new PostgresqlSchema.fromModels([GenObj, GenNotNullable]);
      fail("Schema should not generate");
      schema.toString();
    } catch (e) {
      expect(e.message,
          "_GenNotNullable will set relationship 'ref_id' to null on delete, but 'ref_id' may not be null");
    }
  });

  test("Verify schema creates the same named foreign keys as model", () {
    var schema = new PostgresqlSchema.fromModels([GenUser, GenPost]);
    var p = new GenPost();
    var fk = p.foreignKeyForProperty("owner");
    expect(fk, schema.tables[GenPost].columns["owner"].name);
  });
}

@proxy
class GeneratorModel1 extends Model<_GeneratorModel1> implements _GeneratorModel1 {}

class _GeneratorModel1 {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  bool option;

  @Attributes(unique: true)
  double points;

  @Attributes(nullable: true)
  DateTime validDate;
}

@proxy
class GeneratorModel2 extends Model<_GeneratorModel2> implements _GeneratorModel2 {}

class _GeneratorModel2 {
  @Attributes(indexed: true)
  int id;
}

@proxy
class GeneratorModel3 extends Model<_GeneratorModel3> implements _GeneratorModel3 {}

class _GeneratorModel3 {
  @Attributes(defaultValue: "(now() at time zone 'utc')")
  DateTime creationDate;

  @Attributes(defaultValue: "18")
  int id;

  @Attributes(defaultValue: "\$\$dflt\$\$")
  String textValue;

  @Attributes(defaultValue: "true")
  bool option;

  @Attributes(defaultValue: "'1900-01-01T00:00:00.000Z'")
  DateTime otherTime;

  @Attributes(defaultValue: "20.0")
  double value;
}

@proxy
class GenUser extends Model<_GenUser> implements _GenUser {}

class _GenUser {
  @Attributes(primaryKey: true)
  int id;

  String name;

  @RelationshipAttribute(RelationshipType.hasMany, "owner")
  List<GenPost> posts;
}

@proxy
class GenPost extends Model<_GenPost> implements _GenPost {}

class _GenPost {
  @Attributes(primaryKey: true)
  int id;

  String text;

  @Attributes(indexed: true, nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "posts")
  GenUser owner;
}

@proxy
class GenNamed extends Model<_GenNamed> implements _GenNamed {}

class _GenNamed {
  @Attributes(primaryKey: true)
  int id;

  static String tableName() {
    return "GenNamed";
  }
}

@proxy
class GenOwner extends Model<_GenOwner> implements _GenOwner {}

class _GenOwner {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  @RelationshipAttribute(RelationshipType.hasOne, "owner")
  GenAuth auth;
}

@proxy
class GenAuth extends Model<_GenAuth> implements _GenAuth {}

class _GenAuth {
  @Attributes(primaryKey: true)
  int id;

  @Attributes(nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "auth")
  GenOwner owner;
}

@proxy
class GenLeft extends Model<_GenLeft> implements _GenLeft {}

class _GenLeft {
  @Attributes(primaryKey: true)
  int id;

  @RelationshipAttribute(RelationshipType.hasMany, "left")
  List<GenJoin> join;
}

@proxy
class GenRight extends Model<_GenRight> implements _GenRight {}

class _GenRight {
  @Attributes(primaryKey: true)
  int id;

  @RelationshipAttribute(RelationshipType.hasMany, "right")
  List<GenJoin> join;
}

@proxy
class GenJoin extends Model<_GenJoin> implements _GenJoin {}

class _GenJoin {
  @Attributes(nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "join")
  GenLeft left;

  @Attributes(nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "join")
  GenRight right;
}

@proxy
class GenObj extends Model<_GenObj> implements _GenObj {}

class _GenObj {
  @Attributes(primaryKey: true)
  int id;

  @RelationshipAttribute(RelationshipType.hasOne, "ref")
  GenNotNullable gen;
}

@proxy
class GenNotNullable extends Model<_GenNotNullable> implements _GenNotNullable {}

class _GenNotNullable {
  @Attributes(primaryKey: true)
  int id;

  @Attributes(nullable: false)
  @RelationshipAttribute(RelationshipType.belongsTo, "gen",
      deleteRule: RelationshipDeleteRule.nullify)
  GenObj ref;
}
