import 'package:monadart/monadart.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {});

  tearDown(() {});

  test("Property tables generate appropriate postgresql commands", () {
    var cmd = new PostgresqlSchema.fromModels([GeneratorModel1]).toString();

    expect(cmd,
        "create table GeneratorModel1 (id bigserial primary key,name text not null,option boolean not null,points double precision not null unique,validDate timestamp null);\n");
  });

  test("Create temporary table", () {
    var cmd = new PostgresqlSchema.fromModels([GeneratorModel1],
        temporary: true).toString();
    expect(cmd,
        "create temporary table GeneratorModel1 (id bigserial primary key,name text not null,option boolean not null,points double precision not null unique,validDate timestamp null);\n");
  });

  test("Create table with indices", () {
    var cmd = new PostgresqlSchema.fromModels([GeneratorModel2]).toString();

    expect(cmd,
        "create table GeneratorModel2 (id int not null);\ncreate index GeneratorModel2_id_idx on GeneratorModel2 (id);\n");
  });

  test("Create multiple tables with trailing index", () {
    var cmd =
        new PostgresqlSchema.fromModels([GeneratorModel1, GeneratorModel2])
            .toString();

    expect(cmd,
        "create table GeneratorModel1 (id bigserial primary key,name text not null,option boolean not null,points double precision not null unique,validDate timestamp null);\ncreate table GeneratorModel2 (id int not null);\ncreate index GeneratorModel2_id_idx on GeneratorModel2 (id);\n");
  });

  test("Default values are properly serialized", () {
    var cmd = new PostgresqlSchema.fromModels([GeneratorModel3]).toString();
    expect(cmd,
        "create table GeneratorModel3 (creationDate timestamp not null default (now() at time zone 'utc'),id int not null default 18,option boolean not null default true,otherTime timestamp not null default '1900-01-01T00:00:00.000Z',textValue text not null default \$\$dflt\$\$,value double precision not null default 20.0);\n");
  });

  test("Table without tableName() defaults to clas name", () {
    var cmd = new PostgresqlSchema.fromModels([GenUnnamed]).toString();
    expect(cmd, "create table GenUnnamed (id int primary key);\n");
  });

  test("One-to-one relationships are generated", () {
    var schema = new PostgresqlSchema.fromModels([GenOwner, GenAuth]);

    var cmds = schema.schemaDefinition();

    expect(
        cmds.contains("create table GenOwner (id bigserial primary key)"), true,
        reason: "GenOwner");
    expect(
        cmds.contains(
            "create table GenAuth (id int primary key,owner_id bigint null unique)"),
        true,
        reason: "GenAuth");
    expect(cmds.contains("create index GenAuth_owner_id_idx on GenAuth (owner_id)"), true);

    expect(
        cmds.contains(
            "alter table only GenAuth add foreign key (owner_id) references GenOwner (id) on delete set null"),
        true,
        reason: "Alter");
    expect(cmds.length, 4);
  });

  test("One-to-many relationships are generated", () {
    var schema = new PostgresqlSchema.fromModels([GenUser, GenPost]);
    var cmds = schema.schemaDefinition();

    expect(
        cmds.contains(
            "create table GenUser (id int primary key,name text not null)"),
        true,
        reason: "GenUser table");
    expect(
        cmds.contains(
            "create table GenPost (id int primary key,owner_id int null,text text not null)"),
        true,
        reason: "GenPost table");
    expect(
        cmds.contains(
            "create index GenPost_owner_id_idx on GenPost (owner_id)"),
        true,
        reason: "GenPost index");
    expect(
        cmds.contains(
            "alter table only GenPost add foreign key (owner_id) references GenUser (id) on delete set null"),
        true,
        reason: "Foreign key constraint");
    expect(cmds.length, 4);
  });

  test("Many-to-many relationships are generated", () {
    var schema = new PostgresqlSchema.fromModels([GenLeft, GenRight, GenJoin]);
    var cmds = schema.schemaDefinition();

    expect(cmds.contains("create table GenLeft (id int primary key)"), true,
        reason: "GenLeft table");
    expect(cmds.contains("create table GenRight (id int primary key)"), true,
        reason: "GenRight table");
    expect(
        cmds.contains(
            "create table GenJoin (left_id int null,right_id int null)"),
        true,
        reason: "GenJoin table");
    expect(
        cmds.contains(
            "alter table only GenJoin add foreign key (left_id) references GenLeft (id) on delete set null"),
        true,
        reason: "Left constraint");
    expect(
        cmds.contains(
            "alter table only GenJoin add foreign key (right_id) references GenRight (id) on delete set null"),
        true,
        reason: "Right constraint");
    expect(cmds.contains("create index GenJoin_left_id_idx on GenJoin (left_id)"), true);
    expect(cmds.contains("create index GenJoin_right_id_idx on GenJoin (right_id)"), true);
    expect(cmds.length, 7);
  });

  test("Serial types in relationships are properly inversed", () {
    var schema = new PostgresqlSchema.fromModels([GenOwner, GenAuth]);
    var cmds = schema.schemaDefinition();
    expect(
        cmds.contains(
            "create table GenAuth (id int primary key,owner_id bigint null unique)"),
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
          "GenNotNullable will set relationship 'ref_id' to null on delete, but 'ref_id' may not be null");
    }
  });
}

@ModelBacking(GeneratorModel1Backing)
@proxy
class GeneratorModel1 extends Model implements GeneratorModel1Backing {
}

class GeneratorModel1Backing {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  bool option;

  @Attributes(unique: true)
  double points;

  @Attributes(nullable: true)
  DateTime validDate;

  static String tableName() {
    return "GeneratorModel1";
  }
}

@ModelBacking(GeneratorModel2Backing)
@proxy
class GeneratorModel2 extends Model implements GeneratorModel2Backing {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GeneratorModel2Backing {
  @Attributes(indexed: true)
  int id;

  static String tableName() {
    return "GeneratorModel2";
  }
}

@ModelBacking(GeneratorModel3Backing)
@proxy
class GeneratorModel3 extends Model implements GeneratorModel3Backing {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GeneratorModel3Backing {
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

  static String tableName() {
    return "GeneratorModel3";
  }
}

@ModelBacking(GenUserBacking)
@proxy
class GenUser extends Model implements GenUserBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenUserBacking {
  @Attributes(primaryKey: true)
  int id;

  String name;

  @RelationshipAttribute(RelationshipType.hasMany, "owner")
  List<GenPost> posts;

  static String tableName() {
    return "GenUser";
  }
}

@ModelBacking(GenPostBacking)
@proxy
class GenPost extends Model implements GenPostBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenPostBacking {
  @Attributes(primaryKey: true)
  int id;

  String text;

  @Attributes(indexed: true, nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "posts")
  GenUser owner;

  static String tableName() {
    return "GenPost";
  }
}

@ModelBacking(GenUnnamedBacking)
@proxy
class GenUnnamed extends Model implements GenUnnamedBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenUnnamedBacking {
  @Attributes(primaryKey: true)
  int id;
}

@ModelBacking(GenOwnerBacking)
@proxy
class GenOwner extends Model implements GenOwnerBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenOwnerBacking {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  @RelationshipAttribute(RelationshipType.hasOne, "owner")
  GenAuth auth;
}

@ModelBacking(GenAuthBacking)
@proxy
class GenAuth extends Model implements GenAuthBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenAuthBacking {
  @Attributes(primaryKey: true)
  int id;

  @Attributes(nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "auth")
  GenOwner owner;
}

@ModelBacking(GenLeftBacking)
@proxy
class GenLeft extends Model implements GenLeftBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenLeftBacking {
  @Attributes(primaryKey: true)
  int id;

  @RelationshipAttribute(RelationshipType.hasMany, "left")
  List<GenJoin> join;
}

@ModelBacking(GenRightBacking)
@proxy
class GenRight extends Model implements GenRightBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenRightBacking {
  @Attributes(primaryKey: true)
  int id;

  @RelationshipAttribute(RelationshipType.hasMany, "right")
  List<GenJoin> join;
}

@ModelBacking(GenJoinBacking)
@proxy
class GenJoin extends Model implements GenJoinBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenJoinBacking {
  @Attributes(nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "join")
  GenLeft left;

  @Attributes(nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "join")
  GenRight right;
}

@ModelBacking(GenObjBacking)
@proxy
class GenObj extends Model implements GenObjBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenObjBacking {
  @Attributes(primaryKey: true)
  int id;

  @RelationshipAttribute(RelationshipType.hasOne, "ref")
  GenNotNullable gen;
}

@ModelBacking(GenNotNullableBacking)
@proxy
class GenNotNullable extends Model implements GenNotNullableBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class GenNotNullableBacking {
  @Attributes(primaryKey: true)
  int id;

  @Attributes(nullable: false)
  @RelationshipAttribute(RelationshipType.belongsTo, "gen",
      deleteRule: RelationshipDeleteRule.nullify)
  GenObj ref;
}
