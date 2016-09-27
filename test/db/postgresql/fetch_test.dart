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
        new SortDescriptor("email", SortOrder.ascending)
      ]
      ..predicate = new Predicate("email like @key", {"key": "asc%"});

    var result = await req.fetch();

    for (int i = 0; i < 10; i++) {
      expect(result[i].email, "asc${i}@a.com");
    }

    req = new Query<TestModel>()
      ..sortDescriptors = [
        new SortDescriptor("id", SortOrder.ascending)
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
        new SortDescriptor("email", SortOrder.descending)
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
        new SortDescriptor("name", SortOrder.ascending),
        new SortDescriptor("email", SortOrder.descending)
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
      expect(e.toString(), "Property badkey in resultKeys does not exist on simple");
      expect(e.event, QueryExceptionEvent.internalFailure);
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

    var query = new Query<GenPost>();
    query.matchOn["owner"] = whereRelatedByValue(u1.id);
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



  test("Omits specific keys", () async {
    context = await contextWithModels([Omit]);

    var iq = new Query<Omit>()..values = (new Omit()..text = "foobar");

    var result = await iq.insert();
    expect(result.id, greaterThan(0));
    expect(result.backingMap["text"], isNull);

    var matcher = new Query<Omit>()
      ..matchOn["id"] = whereEqualTo(result.id);
    var fq = new Query<Omit>()..predicate = matcher.predicate;

    var fResult = await fq.fetchOne();
    expect(fResult.id, result.id);
    expect(fResult.backingMap["text"], isNull);
  });

}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;

  @ColumnAttributes(nullable: true, unique: true)
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

  OrderedSet<GenPost> posts;

  static String tableName() {
    return "GenUser";
  }
}

class GenPost extends Model<_GenPost> implements _GenPost {}
class _GenPost {
  @primaryKey
  int id;

  String text;

  @RelationshipInverse(#posts, onDelete: RelationshipDeleteRule.cascade, isRequired: false)
  GenUser owner;
}

class Omit extends Model<_Omit> implements _Omit {}
class _Omit {
  @primaryKey
  int id;

  @ColumnAttributes(omitByDefault: true)
  String text;
}
