import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ManagedContext context;
  tearDown(() async {
    await context?.close();
    context = null;
  });

  test("Fetching an object gets entire object", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel(name: "Joe", email: "a@a.com");
    var req = new Query<TestModel>(context)..values = m;
    var item = await req.insert();

    req = new Query<TestModel>(context)
      ..predicate = new QueryPredicate("id = @id", {"id": item.id});
    item = await req.fetchOne();

    expect(item.name, "Joe");
    expect(item.email, "a@a.com");
  });

  test("Query with dynamic entity and mis-matched context throws exception", () async {
    context = await contextWithModels([TestModel]);

    var someOtherContext = new ManagedContext(new ManagedDataModel([]), null);
    try {
      new Query.forEntity(context.dataModel.entityForType(TestModel), someOtherContext);
      expect(true, false);
    } on StateError catch (e) {
      expect(e.toString(), allOf([contains("'simple'"), contains("is from different context")]));
    }
  });

  test("Specifying resultProperties works", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel(name: "Joe", email: "b@a.com");
    var req = new Query<TestModel>(context)..values = m;

    var item = await req.insert();
    var id = item.id;

    req = new Query<TestModel>(context)
      ..predicate = new QueryPredicate("id = @id", {"id": item.id})
      ..returningProperties((t) => [t.id, t.name]);

    item = await req.fetchOne();

    expect(item.name, "Joe");
    expect(item.id, id);
    expect(item.email, isNull);
  });

  test("Returning properties for undefined attributes fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel(name: "Joe", email: "b@a.com");
    var req = new Query<TestModel>(context)..values = m;

    await req.insert();

    try {
      req = new Query<TestModel>(context)
        ..returningProperties((t) => [t.id, t["foobar"]]);
      fail("unreachable");
    } on ArgumentError catch (e) {
      expect(e.toString(), allOf([
        contains("'foobar'"),
        contains("'TestModel'"),
      ]));
    }
  });

  test("Ascending sort descriptors work", () async {
    context = await contextWithModels([TestModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel(name: "Joe$i", email: "asc$i@a.com");
      var req = new Query<TestModel>(context)..values = m;
      await req.insert();
    }

    var req = new Query<TestModel>(context)
      ..sortBy((t) => t.email, QuerySortOrder.ascending)
      ..predicate = new QueryPredicate("email like @key", {"key": "asc%"});

    var result = await req.fetch();

    for (int i = 0; i < 10; i++) {
      expect(result[i].email, "asc$i@a.com");
    }

    req = new Query<TestModel>(context)..sortBy((t) => t.id, QuerySortOrder.ascending);
    result = await req.fetch();

    int idIndex = 0;
    for (TestModel m in result) {
      int next = m.id;
      expect(next, greaterThan(idIndex));
      idIndex = next;
    }
  });

  test("Descending sort descriptors work", () async {
    context = await contextWithModels([TestModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel(name: "Joe$i", email: "desc$i@a.com");

      var req = new Query<TestModel>(context)..values = m;

      await req.insert();
    }

    var req = new Query<TestModel>(context)
      ..sortBy((t) => t.email, QuerySortOrder.descending)
      ..predicate = new QueryPredicate("email like @key", {"key": "desc%"});
    var result = await req.fetch();

    for (int i = 0; i < 10; i++) {
      int v = 9 - i;
      expect(result[i].email, "desc$v@a.com");
    }
  });

  test("Cannot sort by property that doesn't exist", () async {
    context = await contextWithModels([TestModel]);
    try {
      new Query<TestModel>(context)
        ..sortBy((u) => u["nonexisting"], QuerySortOrder.ascending);
      expect(true, false);
    } on ArgumentError catch (e) {
      expect(e.toString(), allOf([
        contains("does not exist on"),
        contains("'nonexisting'"),
        contains("'TestModel'"),
      ]));
    }
  });

  test("Cannot sort by relationship property", () async {
    context = await contextWithModels([GenUser, GenPost]);
    try {
      new Query<GenUser>(context)
          ..sortBy((u) => u.posts, QuerySortOrder.ascending);
      expect(true, false);
    } on ArgumentError catch (e) {
      expect(e.toString(), allOf([
        contains("'posts'"),
        contains("'GenUser'"),
        contains("is a relationship"),
      ]));
    }
  });

  test("Order by multiple sort descriptors work", () async {
    context = await contextWithModels([TestModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel(name: "Joe${i%2}", email: "multi$i@a.com");

      var req = new Query<TestModel>(context)..values = m;

      await req.insert();
    }

    var req = new Query<TestModel>(context)
      ..sortBy((t) => t.name, QuerySortOrder.ascending)
      ..sortBy((t) => t.email, QuerySortOrder.descending)
      ..predicate = new QueryPredicate("email like @key", {"key": "multi%"});

    var result = await req.fetch();

    expect(result[0].name, "Joe0");
    expect(result[0].email, "multi8@a.com");

    expect(result[1].name, "Joe0");
    expect(result[1].email, "multi6@a.com");

    expect(result[2].name, "Joe0");
    expect(result[2].email, "multi4@a.com");

    expect(result[3].name, "Joe0");
    expect(result[3].email, "multi2@a.com");

    expect(result[4].name, "Joe0");
    expect(result[4].email, "multi0@a.com");

    expect(result[5].name, "Joe1");
    expect(result[5].email, "multi9@a.com");

    expect(result[6].name, "Joe1");
    expect(result[6].email, "multi7@a.com");

    expect(result[7].name, "Joe1");
    expect(result[7].email, "multi5@a.com");

    expect(result[8].name, "Joe1");
    expect(result[8].email, "multi3@a.com");

    expect(result[9].name, "Joe1");
    expect(result[9].email, "multi1@a.com");
  });

  test("Fetching an invalid key fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel(name: "invkey", email: "invkey@a.com");

    var req = new Query<TestModel>(context)..values = m;
    await req.insert();


    try {
      req = new Query<TestModel>(context)
        ..returningProperties((t) => [t.id, t["badkey"]]);

      fail("unreachable");
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Property 'badkey' does not exist on 'TestModel'"));
    }
  });

  test("Value for foreign key in predicate", () async {
    context = await contextWithModels([GenUser, GenPost]);

    var u1 = new GenUser()..name = "Joe";
    var u2 = new GenUser()..name = "Fred";
    u1 = await (new Query<GenUser>(context)..values = u1).insert();
    u2 = await (new Query<GenUser>(context)..values = u2).insert();

    for (int i = 0; i < 5; i++) {
      var p1 = new GenPost()..text = "${2 * i}";
      p1.owner = u1;
      await (new Query<GenPost>(context)..values = p1).insert();

      var p2 = new GenPost()..text = "${2 * i + 1}";
      p2.owner = u2;
      await (new Query<GenPost>(context)..values = p2).insert();
    }

    var req = new Query<GenPost>(context)
      ..predicate = new QueryPredicate("owner_id = @id", {"id": u1.id});
    var res = await req.fetch();
    expect(res.length, 5);
    expect(
        res
            .map((p) => p.text)
            .where((text) => num.parse(text) % 2 == 0)
            .toList()
            .length,
        5);

    var query = new Query<GenPost>(context);
    query.where((o) => o.owner).identifiedBy(u1.id);
    res = await query.fetch();

    GenUser user = res.first.owner;
    expect(user, isNotNull);
    expect(res.length, 5);
    expect(
        res
            .map((p) => p.text)
            .where((text) => num.parse(text) % 2 == 0)
            .toList()
            .length,
        5);
  });

  test("Fetch object with null reference", () async {
    context = await contextWithModels([GenUser, GenPost]);
    var p1 = await (new Query<GenPost>(context)..values = (new GenPost()..text = "1"))
        .insert();

    var req = new Query<GenPost>(context);
    p1 = await req.fetchOne();

    expect(p1.owner, isNull);
  });

  test("Omits specific keys", () async {
    context = await contextWithModels([Omit]);

    var iq = new Query<Omit>(context)..values = (new Omit()..text = "foobar");

    var result = await iq.insert();
    expect(result.id, greaterThan(0));
    expect(result.backing.contents["text"], isNull);

    var fq = new Query<Omit>(context)
      ..predicate = new QueryPredicate("id=@id", {"id": result.id});

    var fResult = await fq.fetchOne();
    expect(fResult.id, result.id);
    expect(fResult.backing.contents["text"], isNull);
  });

  test(
      "Throw exception when fetchOne returns more than one because the fetchLimit can't be applied to joins",
      () async {
    context = await contextWithModels([GenUser, GenPost]);

    var objects = [new GenUser()..name = "Joe", new GenUser()..name = "Bob"];

    for (var o in objects) {
      var req = new Query<GenUser>(context)..values = o;
      await req.insert();
    }

    try {
      var q = new Query<GenUser>(context)..join(set: (u) => u.posts);

      await q.fetchOne();

      expect(true, false);
    } on StateError catch (e) {
      expect(
          e.toString(),
          contains("'fetchOne' returned more than one row from 'GenUser'"));
    }
  });

  test(
      "Including RelationshipInverse property can only be done by using name of property",
      () async {
    context = await contextWithModels([GenUser, GenPost]);

    var u1 = await (new Query<GenUser>(context)..values.name = "Joe").insert();

    await (new Query<GenPost>(context)
          ..values.text = "text"
          ..values.owner = u1)
        .insert();

    var q = new Query<GenPost>(context)..returningProperties((p) => [p.id, p.owner]);

    var result = await q.fetchOne();
    expect(result.owner.id, 1);
    expect(result.owner.backing.contents.length, 1);


    try {
      q = new Query<GenPost>(context)..returningProperties((p) => [p.id, p["owner_id"]]);
      expect(true, false);
    } on ArgumentError catch (e) {
      expect(e.toString(),
          contains("Property 'owner_id' does not exist on 'GenPost'"));
    }
  });

  test("Can use public accessor to private property", () async {
    context = await contextWithModels([PrivateField]);

    await (new Query<PrivateField>(context)).insert();
    var q = new Query<PrivateField>(context);
    var result = await q.fetchOne();
    expect(result.public, "x");
  });

  test("When fetching valid enum value from db, is available as enum value and in where", () async {
    context = await contextWithModels([EnumObject]);

    var q = new Query<EnumObject>(context)
      ..values.enumValues = EnumValues.abcd;

    await q.insert();

    q = new Query<EnumObject>(context);
    var result = await q.fetchOne();
    expect(result.enumValues, EnumValues.abcd);
    expect(result.asMap()["enumValues"], "abcd");

    q = new Query<EnumObject>(context)
      ..where((o) => o.enumValues).equalTo(EnumValues.abcd);
    result = await q.fetchOne();
    expect(result, isNotNull);

    q = new Query<EnumObject>(context)
      ..where((o) => o.enumValues).equalTo(EnumValues.efgh);
    result = await q.fetchOne();
    expect(result, isNull);
  });

  test("When fetching invalid enum value from db, throws error", () async {
    context = await contextWithModels([EnumObject]);

    await context.persistentStore.execute("INSERT INTO _enumobject (enumValues) VALUES ('foobar')");

    try {
      var q = new Query<EnumObject>(context);
      await q.fetch();
      expect(true, false);
    } on StateError catch (e) {
      expect(e.toString(), contains("Database error when retrieving value"));
      expect(e.toString(), contains("invalid option for key 'enumValues'"));
    }
  });

  test("Cannot include relationship in returning properties", () async {
    context = await contextWithModels([GenUser, GenPost]);

    try {
      new Query<GenUser>(context)
        ..returningProperties((p) => [p.posts]);
      fail("unreachable");
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Cannot select has-many or has-one relationship properties")) ;
    }
  });

}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {
  TestModel({String name, String email}) {
    this.name = name;
    this.email = email;
  }
}

class _TestModel {
  @primaryKey
  int id;

  String name;

  @Column(nullable: true, unique: true)
  String email;

  static String tableName() {
    return "simple";
  }

  @override
  String toString() {
    return "TestModel: $id $name $email";
  }
}

class GenUser extends ManagedObject<_GenUser> implements _GenUser {}

class _GenUser {
  @primaryKey
  int id;

  String name;

  ManagedSet<GenPost> posts;

  static String tableName() {
    return "GenUser";
  }
}

class GenPost extends ManagedObject<_GenPost> implements _GenPost {}

class _GenPost {
  @primaryKey
  int id;

  String text;

  @Relate(Symbol('posts'),
      onDelete: DeleteRule.cascade, isRequired: false)
  GenUser owner;
}

class Omit extends ManagedObject<_Omit> implements _Omit {}

class _Omit {
  @primaryKey
  int id;

  @Column(omitByDefault: true)
  String text;
}

class PrivateField extends ManagedObject<_PrivateField> implements _PrivateField {
  PrivateField() : super() {
    _private = "x";
  }

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

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}
class _EnumObject {
  @primaryKey
  int id;

  EnumValues enumValues;
}

enum EnumValues {
  abcd, efgh, other18
}