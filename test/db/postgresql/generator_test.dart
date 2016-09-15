import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import '../../helpers.dart';

void main() {
  test("Property tables generate appropriate postgresql commands", () {
    expect(commandsForModelTypes([GeneratorModel1]),
        "create table _GeneratorModel1 (id bigserial primary key,name text not null,option boolean not null,points double precision not null unique,validDate timestamp null);");
  });

  test("Create temporary table", () {
    expect(commandsForModelTypes([GeneratorModel1], temporary: true),
        "create temporary table _GeneratorModel1 (id bigserial primary key,name text not null,option boolean not null,points double precision not null unique,validDate timestamp null);");
  });

  test("Create table with indices", () {
    expect(commandsForModelTypes([GeneratorModel2]),
        "create table _GeneratorModel2 (id int primary key);\ncreate index _GeneratorModel2_id_idx on _GeneratorModel2 (id);");
  });

  test("Create multiple tables with trailing index", () {
    expect(commandsForModelTypes([GeneratorModel1, GeneratorModel2]),
        "create table _GeneratorModel1 (id bigserial primary key,name text not null,option boolean not null,points double precision not null unique,validDate timestamp null);\ncreate table _GeneratorModel2 (id int primary key);\ncreate index _GeneratorModel2_id_idx on _GeneratorModel2 (id);");
  });

  test("Default values are properly serialized", () {
    expect(commandsForModelTypes([GeneratorModel3]),
        "create table _GeneratorModel3 (creationDate timestamp not null default (now() at time zone 'utc'),id int primary key,option boolean not null default true,otherTime timestamp not null default '1900-01-01T00:00:00.000Z',textValue text not null default \$\$dflt\$\$,value double precision not null default 20.0);");
  });

  test("Table with tableName() overrides class name", () {
    expect(commandsForModelTypes([GenNamed]),
        "create table GenNamed (id int primary key);");
  });

  test("One-to-one relationships are generated", () {
    var cmds = commandsForModelTypes([GenOwner, GenAuth]);
    expect(cmds.contains("create table _GenOwner (id bigserial primary key)"), true);
    expect(cmds.contains("create table _GenAuth (id int primary key,owner_id bigint null unique)"), true);
    expect(cmds.contains("create index _GenAuth_owner_id_idx on _GenAuth (owner_id)"), true);
    expect(cmds.contains("alter table only _GenAuth add foreign key (owner_id) references _GenOwner (id) on delete cascade"), true);
    expect(cmds.split("\n").length, 4);
  });

  test("One-to-many relationships are generated", () {
    var cmds = commandsForModelTypes([GenUser, GenPost]);

    expect(cmds.contains("create table _GenUser (id int primary key,name text not null)"), true);
    expect(cmds.contains("create table _GenPost (id int primary key,owner_id int null,text text not null)"), true);
    expect(cmds.contains("create index _GenPost_owner_id_idx on _GenPost (owner_id)"), true);
    expect(cmds.contains("alter table only _GenPost add foreign key (owner_id) references _GenUser (id) on delete restrict"), true);
    expect(cmds.split("\n").length, 4);
  });

  test("Many-to-many relationships are generated", () {
    var cmds = commandsForModelTypes([GenLeft, GenRight, GenJoin]);

    expect(cmds.contains("create table _GenLeft (id int primary key)"), true);
    expect(cmds.contains("create table _GenRight (id int primary key)"), true);
    expect(cmds.contains("create table _GenJoin (id bigserial primary key,left_id int null,right_id int null)"), true);
    expect(cmds.contains("alter table only _GenJoin add foreign key (left_id) references _GenLeft (id) on delete set null"), true);
    expect(cmds.contains("alter table only _GenJoin add foreign key (right_id) references _GenRight (id) on delete set null"), true);
    expect(cmds.contains("create index _GenJoin_left_id_idx on _GenJoin (left_id)"), true);
    expect(cmds.contains("create index _GenJoin_right_id_idx on _GenJoin (right_id)"), true);
    expect(cmds.split("\n").length, 7);
  });

  test("Serial types in relationships are properly inversed", () {
    var cmds = commandsForModelTypes([GenOwner, GenAuth]);
    expect(cmds.contains("create table _GenAuth (id int primary key,owner_id bigint null unique)"), true);
  });
}

class GeneratorModel1 extends Model<_GeneratorModel1> implements _GeneratorModel1 {}

class _GeneratorModel1 {
  @primaryKey
  int id;

  String name;

  bool option;

  @AttributeHint(unique: true)
  double points;

  @AttributeHint(nullable: true)
  DateTime validDate;
}

class GeneratorModel2 extends Model<_GeneratorModel2> implements _GeneratorModel2 {}
class _GeneratorModel2 {
  @AttributeHint(primaryKey: true, indexed: true)
  int id;
}

class GeneratorModel3 extends Model<_GeneratorModel3> implements _GeneratorModel3 {}
class _GeneratorModel3 {
  @AttributeHint(defaultValue: "(now() at time zone 'utc')")
  DateTime creationDate;

  @AttributeHint(primaryKey: true, defaultValue: "18")
  int id;

  @AttributeHint(defaultValue: "\$\$dflt\$\$")
  String textValue;

  @AttributeHint(defaultValue: "true")
  bool option;

  @AttributeHint(defaultValue: "'1900-01-01T00:00:00.000Z'")
  DateTime otherTime;

  @AttributeHint(defaultValue: "20.0")
  double value;
}

class GenUser extends Model<_GenUser> implements _GenUser {}

class _GenUser {
  @AttributeHint(primaryKey: true)
  int id;

  String name;

  OrderedSet<GenPost> posts;
}

class GenPost extends Model<_GenPost> implements _GenPost {}
class _GenPost {
  @AttributeHint(primaryKey: true)
  int id;

  String text;

  @RelationshipInverse(#posts, isRequired: false, onDelete: RelationshipDeleteRule.restrict)
  GenUser owner;
}

class GenNamed extends Model<_GenNamed> implements _GenNamed {}

class _GenNamed {
  @AttributeHint(primaryKey: true)
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
  @AttributeHint(primaryKey: true)
  int id;

  @RelationshipInverse(#auth, isRequired: false, onDelete: RelationshipDeleteRule.cascade)
  GenOwner owner;
}

class GenLeft extends Model<_GenLeft> implements _GenLeft {}
class _GenLeft {
  @AttributeHint(primaryKey: true)
  int id;

  OrderedSet<GenJoin> join;
}

class GenRight extends Model<_GenRight> implements _GenRight {}
class _GenRight {
  @AttributeHint(primaryKey: true)
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
