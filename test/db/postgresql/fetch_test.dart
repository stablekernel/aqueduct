import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ModelContext context = null;

  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Fetching an object gets entire object", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "Joe"
      ..email = "a@a.com";

    var req = new Query<TestModel>()..values = m;
    var item = await req.insert();

    req = new Query<TestModel>()
      ..predicate = new Predicate("id = @id", {"id": item.id});
    item = await req.fetchOne();

    expect(item.name, "Joe");
    expect(item.email, "a@a.com");
  });

  test("Specifying resultKeys works", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "Joe"
      ..email = "b@a.com";
    var req = new Query<TestModel>()..values = m;

    var item = await req.insert();
    var id = item.id;

    req = new Query<TestModel>()
      ..predicate = new Predicate("id = @id", {"id": item.id})
      ..resultProperties = ["id", "name"];

    item = await req.fetchOne();

    expect(item.name, "Joe");
    expect(item.id, id);
    expect(item.email, isNull);
  });

  test("Ascending sort descriptors work", () async {
    context = await contextWithModels([TestModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel()
        ..name = "Joe${i}"
        ..email = "asc${i}@a.com";
      var req = new Query<TestModel>()..values = m;
      await req.insert();
    }

    var req = new Query<TestModel>()
      ..sortDescriptors = [
        new SortDescriptor("email", SortDescriptorOrder.ascending)
      ]
      ..predicate = new Predicate("email like @key", {"key": "asc%"});

    var result = await req.fetch();

    for (int i = 0; i < 10; i++) {
      expect(result[i].email, "asc${i}@a.com");
    }

    req = new Query<TestModel>()
      ..sortDescriptors = [
        new SortDescriptor("id", SortDescriptorOrder.ascending)
      ];
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
      var m = new TestModel()
        ..name = "Joe${i}"
        ..email = "desc${i}@a.com";

      var req = new Query<TestModel>()..values = m;

      await req.insert();
    }

    var req = new Query<TestModel>()
      ..sortDescriptors = [
        new SortDescriptor("email", SortDescriptorOrder.descending)
      ]
      ..predicate = new Predicate("email like @key", {"key": "desc%"});
    var result = await req.fetch();

    for (int i = 0; i < 10; i++) {
      int v = 9 - i;
      expect(result[i].email, "desc${v}@a.com");
    }
  });

  test("Order by multiple sort descriptors work", () async {
    context = await contextWithModels([TestModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel()
        ..name = "Joe${i%2}"
        ..email = "multi${i}@a.com";

      var req = new Query<TestModel>()..values = m;

      await req.insert();
    }

    var req = new Query<TestModel>()
      ..sortDescriptors = [
        new SortDescriptor("name", SortDescriptorOrder.ascending),
        new SortDescriptor("email", SortDescriptorOrder.descending)
      ]
      ..predicate = new Predicate("email like @key", {"key": "multi%"});

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

    var m = new TestModel()
      ..name = "invkey"
      ..email = "invkey@a.com";

    var req = new Query<TestModel>()..values = m;
    await req.insert();

    req = new Query<TestModel>();
    req.resultProperties = ["id", "badkey"];

    var successful = false;
    try {
      await req.fetch();
      successful = true;
    } on QueryException catch (e) {
      expect(e.message, "Property badkey in resultKeys does not exist on simple");
      expect(e.errorCode, -1);
      expect(e.statusCode, 500);
    }
    expect(successful, false);
  });

  test("Value for foreign key in predicate", () async {
    context = await contextWithModels([GenUser, GenPost]);

    var u1 = new GenUser()..name = "Joe";
    var u2 = new GenUser()..name = "Fred";
    u1 = await (new Query<GenUser>()..values = u1).insert();
    u2 = await (new Query<GenUser>()..values = u2).insert();

    for (int i = 0; i < 5; i++) {
      var p1 = new GenPost()..text = "${2 * i}";
      p1.owner = u1;
      await (new Query<GenPost>()..values = p1).insert();

      var p2 = new GenPost()..text = "${2 * i + 1}";
      p2.owner = u2;
      await (new Query<GenPost>()..values = p2).insert();
    }

    var req = new Query<GenPost>()
      ..predicate = new Predicate("owner_id = @id", {"id": u1.id});
    var res = await req.fetch();
    expect(res.length, 5);
    expect(res.map((p) => p.text)
            .where((text) => num.parse(text) % 2 == 0)
            .toList()
            .length, 5);

    var query = new ModelQuery<GenPost>();
    query["owner"] = whereRelatedByValue(u1.id);
    res = await query.fetch();

    GenUser user = res.first.owner;
    expect(user, isNotNull);
    expect(res.length, 5);
    expect(res.map((p) => p.text)
            .where((text) => num.parse(text) % 2 == 0)
            .toList()
            .length, 5);
  });

  test("Fetch object with null reference", () async {
    context = await contextWithModels([GenUser, GenPost]);
    var p1 = await (new Query<GenPost>()..values = (new GenPost()..text = "1")).insert();

    var req = new Query<GenPost>();
    p1 = await req.fetchOne();

    expect(p1.owner, isNull);
  });

  test("Offset", () async {
    context = await contextWithModels([PageableTestModel]);

    for (int i = 0; i < 10; i++) {
      var p = new PageableTestModel()..value = "${i}";
      await (new Query<PageableTestModel>()..values = p).insert();
    }

    var q = new Query<PageableTestModel>()
      ..fetchLimit = 1
      ..offset = 2;

    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.value, "2");

    q = new Query<PageableTestModel>()
      ..fetchLimit = 1
      ..offset = 10;

    results = await q.fetch();
    expect(results.length, 0);

    q = new Query<PageableTestModel>()
      ..sortDescriptors = [
        new SortDescriptor("id", SortDescriptorOrder.descending)
      ]
      ..fetchLimit = 2
      ..offset = 2;

    results = await q.fetch();
    expect(results.length, 2);
    expect(results.first.value, "7");
    expect(results[1].value, "6");
  });

  test("Omits specific keys", () async {
    context = await contextWithModels([Omit]);

    var iq = new Query<Omit>()..values = (new Omit()..text = "foobar");

    var result = await iq.insert();
    expect(result.id, greaterThan(0));
    expect(result.dynamicBacking["text"], isNull);

    var matcher = new ModelQuery<Omit>()
      ..["id"] = whereEqualTo(result.id);
    var fq = new Query<Omit>()..predicate = matcher.predicate;

    var fResult = await fq.fetchOne();
    expect(fResult.id, result.id);
    expect(fResult.dynamicBacking["text"], isNull);
  });

  test("Paging", () async {
    context = await contextWithModels([PageableTestModel]);

    /*
     |1 2 3 4 5 6 7 8 9 0|
     ---------------------
    x|- - - - >          |
     |x - - - - >        |
    x|- - - - - - - - - -|>
     |          x - - - >|
     |          x - - - -|>
     |                  x|>
     |                   |x>
 nil |- - - - - - - - - -|>
 nil |- - - - >          |
   <x|                   |
    <|x                  |
    <|- - - x            |
     |< - - - x          |
    <|- - - - - - - - - -|x
     |        < - - - - x|
     |          < - - - -|x
    <|- - - - - - - - - -| nil
     |          < - - - -| nil
     ---------------------
     */

    var check = (List checkIDs, List values) {
      expect(checkIDs.length, values.length);
      var ids = values.map((v) => v.id).toList();
      for (int i = 0; i < ids.length; i++) {
        expect(ids[i], checkIDs[i]);
      }
    };

    for (int i = 0; i < 10; i++) {
      var p = new PageableTestModel()..value = "${i}";

      await (new Query<PageableTestModel>()..values = p).insert();
    }

    // after

    // select * from t where id > 0 order by id asc limit 5;
    var pageObject = new QueryPage(PageDirection.after, "id", 0);
    var req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 5;
    var res = await req.fetch();
    check([1, 2, 3, 4, 5], res);

    // select * from t where id > 1 order by id asc limit 5;
    pageObject = new QueryPage(PageDirection.after, "id", 1);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 5;
    res = await req.fetch();
    check([2, 3, 4, 5, 6], res);

    // select * from t where id > 0 order by id asc limit 15;
    pageObject = new QueryPage(PageDirection.after, "id", 0);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 15;
    res = await req.fetch();
    check([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], res);

    // select * from t where id > 6 order by id asc limit 4;
    pageObject = new QueryPage(PageDirection.after, "id", 6);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 4;
    res = await req.fetch();
    check([7, 8, 9, 10], res);

    // select * from t where id > 6 order by id asc limit 5
    pageObject = new QueryPage(PageDirection.after, "id", 6);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 5;
    res = await req.fetch();
    check([7, 8, 9, 10], res);

    // select * from t where id > 10 order by id asc limit 5
    pageObject = new QueryPage(PageDirection.after, "id", 10);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 5;
    res = await req.fetch();
    expect(res.length, 0);

    // select * from t where id > 11 order by id asc limit 10
    pageObject = new QueryPage(PageDirection.after, "id", 11);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 10;
    res = await req.fetch();
    expect(res.length, 0);

    // select * from t order by id asc limit 10
    pageObject = new QueryPage(PageDirection.after, "id", null);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 15;
    res = await req.fetch();
    check([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], res);

    // select * from t order by id asc limit 5;
    pageObject = new QueryPage(PageDirection.after, "id", null);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 5;
    res = await req.fetch();
    check([1, 2, 3, 4, 5], res);

    // prior

    // select * from t where id < 0 order by id desc limit 10
    pageObject = new QueryPage(PageDirection.prior, "id", 0);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 10;
    res = await req.fetch();
    expect(res.length, 0);

    // select * from t where id < 1 order by id desc limit 10;
    pageObject = new QueryPage(PageDirection.prior, "id", 1);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 10;
    res = await req.fetch();
    expect(res.length, 0);

    // select * from t where id < 4 order by id desc limit 10;
    pageObject = new QueryPage(PageDirection.prior, "id", 4);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 10;
    res = await req.fetch();
    check([3, 2, 1], res);

    // select * from t where id < 5 order by id desc limit 4;
    pageObject = new QueryPage(PageDirection.prior, "id", 5);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 4;
    res = await req.fetch();
    check([4, 3, 2, 1], res);

    // select * from t where id < 11 order by id desc limit 10;
    pageObject = new QueryPage(PageDirection.prior, "id", 11);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 10;
    res = await req.fetch();
    check([10, 9, 8, 7, 6, 5, 4, 3, 2, 1], res);

    // select * from t where id < 10 order by id desc limit 5;
    pageObject = new QueryPage(PageDirection.prior, "id", 10);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 5;
    res = await req.fetch();
    check([9, 8, 7, 6, 5], res);

    // select * from t where id < 11 order by id desc limit 5
    pageObject = new QueryPage(PageDirection.prior, "id", 11);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 5;
    res = await req.fetch();
    check([10, 9, 8, 7, 6], res);

    // select * from t order by id desc limit 10
    pageObject = new QueryPage(PageDirection.prior, "id", null);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 10;
    res = await req.fetch();
    check([10, 9, 8, 7, 6, 5, 4, 3, 2, 1], res);

    // select * from t order by id desc limit 5
    pageObject = new QueryPage(PageDirection.prior, "id", null);
    req = new Query<PageableTestModel>()
      ..pageDescriptor = pageObject
      ..fetchLimit = 5;
    res = await req.fetch();
    check([10, 9, 8, 7, 6], res);
  });
}

class PageableTestModel extends Model<_PageableTestModel> implements _PageableTestModel {}
class _PageableTestModel {
  @primaryKey
  int id;

  String value;
}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;

  @Attributes(nullable: true, unique: true)
  String email;

  static String tableName() {
    return "simple";
  }

  String toString() {
    return "TestModel: ${id} ${name} ${email}";
  }
}

class GenUser extends Model<_GenUser> implements _GenUser {}
class _GenUser {
  @primaryKey
  int id;

  String name;

  @Relationship(RelationshipType.hasMany, "owner")
  List<GenPost> posts;

  static String tableName() {
    return "GenUser";
  }
}

class GenPost extends Model<_GenPost> implements _GenPost {}
class _GenPost {
  @primaryKey
  int id;

  String text;

  @Relationship(RelationshipType.belongsTo, "posts", deleteRule: RelationshipDeleteRule.cascade, required: false)
  GenUser owner;
}

class Omit extends Model<_Omit> implements _Omit {}
class _Omit {
  @primaryKey
  int id;

  @Attributes(omitByDefault: true)
  String text;
}
