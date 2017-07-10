import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ManagedContext context;

  setUpAll(() async {
    context = await contextWithModels([TestModel, InnerModel]);
    var counter = 0;
    var names = ["Bob", "Fred", "Tim", "Sally", "Kanye", "Lisa"];
    for (var name in names) {
      var q = new Query<TestModel>()
        ..values.name = name
        ..values.email = "$counter@a.com";
      await q.insert();

      counter++;
    }

    var q = new Query<InnerModel>()
      ..values.name = "Bob's"
      ..values.owner = (new TestModel()..id = 1);
    await q.insert();

    q = new Query<InnerModel>()..values.name = "No one's";
    await q.insert();
  });

  tearDownAll(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  group("Equals matcher", () {
    test("Non-string value", () async {
      var q = new Query<TestModel>()..where["id"] = whereEqualTo(1);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = new Query<TestModel>()..where["id"] = whereNot(whereEqualTo(1));
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.id == 1), false);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where["email"] = whereEqualTo("0@a.com");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = new Query<TestModel>()..where["email"] = whereNot(whereEqualTo("0@a.com"));
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.id == 1), false);

      q = new Query<TestModel>()..where["email"] = whereEqualTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 0);

      q = new Query<TestModel>()..where["email"] = whereNot(whereEqualTo("0@A.com"));
      results = await q.fetch();
      expect(results.length, 6);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where["email"] = whereEqualTo("0@A.com", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = new Query<TestModel>()..where["email"] = whereNot(whereEqualTo("0@A.com", caseSensitive: false));
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.email == "0@a.com"), false);
    });
  });


  test("Less than matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereLessThan(3);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results.first.id, 1);
    expect(results.last.id, 2);

    q = new Query<TestModel>()..where["id"] = whereNot(whereLessThan(3));
    results = await q.fetch();
    expect(results.length, 4);
    expect(results.every((tm) => tm.id >= 3), true);
  });

  test("Less than equal to matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereLessThanEqualTo(3);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 2);
    expect(results[2].id, 3);

    q = new Query<TestModel>()..where["id"] = whereNot(whereLessThanEqualTo(3));
    results = await q.fetch();
    expect(results.length, 3);
    expect(results.every((tm) => tm.id > 3), true);
  });

  test("Greater than matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereGreaterThan(4);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 5);
    expect(results[1].id, 6);

    q = new Query<TestModel>()..where["id"] = whereNot(whereGreaterThan(4));
    results = await q.fetch();
    expect(results.length, 4);
    expect(results.every((tm) => tm.id <= 4), true);
  });

  test("Greater than equal to matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereGreaterThanEqualTo(4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 4);
    expect(results[1].id, 5);
    expect(results[2].id, 6);

    q = new Query<TestModel>()..where["id"] = whereNot(whereGreaterThanEqualTo(4));
    results = await q.fetch();
    expect(results.length, 3);
    expect(results.every((tm) => tm.id < 4), true);
  });

  group("Not equal matcher", () {
    test("Non-string value", () async {
      var q = new Query<TestModel>()..where["id"] = whereNotEqualTo(1);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = new Query<TestModel>()..where["id"] = whereNot(whereNotEqualTo(1));
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.id == 1), true);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where["email"] = whereNotEqualTo("0@a.com");
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = new Query<TestModel>()..where["email"] = whereNot(whereNotEqualTo("0@a.com"));
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.id == 1), true);

      q = new Query<TestModel>()..where["email"] = whereNotEqualTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 6);

      q = new Query<TestModel>()..where["email"] = whereNot(whereNotEqualTo("0@A.com"));
      results = await q.fetch();
      expect(results.length, 0);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where["email"] = whereNotEqualTo("0@A.com", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = new Query<TestModel>()..where["email"] = whereNot(whereNotEqualTo("0@A.com", caseSensitive: false));
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.id == 1), true);
    });
  });


  test("whereIn matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereIn([1, 2]);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 1);
    expect(results[1].id, 2);

    q = new Query<TestModel>()..where["id"] = whereNot(whereIn([1, 2]));
    results = await q.fetch();
    expect(results.length, 4);
    expect(results.any((t) => t.id == 1), false);
    expect(results.any((t) => t.id == 2), false);
  });

  test("whereBetween matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereBetween(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);

    q = new Query<TestModel>()..where["id"] = whereNot(whereBetween(2, 4));
    results = await q.fetch();
    expect(results.length, 3);

    results.sort((t1, t2) => t1.id.compareTo(t2.id));
    expect(results[0].id, 1);
    expect(results[1].id, 5);
    expect(results[2].id, 6);
  });

  test("whereOutsideOf matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereOutsideOf(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 5);
    expect(results[2].id, 6);

    q = new Query<TestModel>()..where["id"] = whereNot(whereOutsideOf(2, 4));
    results = await q.fetch();
    expect(results.length, 3);

    results.sort((t1, t2) => t1.id.compareTo(t2.id));
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);
  });

  test("whereRelatedByValue matcher", () async {
    var q = new Query<InnerModel>()..where["owner"] = whereRelatedByValue(1);
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.owner.id, 1);

    // Does not include null values; this is intentional.
    q = new Query<InnerModel>()..where["owner"] = whereNot(whereRelatedByValue(1));
    results = await q.fetch();
    expect(results.length, 0);
  });

  test("whereNull matcher", () async {
    var q = new Query<InnerModel>()..where["owner"] = whereNull;
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "No one's");

    q = new Query<InnerModel>()..where["owner"] = whereNot(whereNull);
    results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob's");
  });

  test("whereNotNull matcher", () async {
    var q = new Query<InnerModel>()..where["owner"] = whereNotNull;
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob's");

    q = new Query<InnerModel>()..where["owner"] = whereNot(whereNotNull);
    results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "No one's");
  });

  group("whereContains matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereContainsString("y");
      var results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.name, "Sally");
      expect(results.last.name, "Kanye");

      q = new Query<TestModel>()..where["name"] = whereNot(whereContainsString("y"));
      results = await q.fetch();
      expect(results.length, 4);
      expect(results.any((tm) => tm.name == "Sally"), false);
      expect(results.any((tm) => tm.name == "Kanye"), false);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereContainsString("Y", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.name, "Sally");
      expect(results.last.name, "Kanye");

      q = new Query<TestModel>()..where["name"] = whereNot(whereContainsString("Y", caseSensitive: false));
      results = await q.fetch();
      expect(results.length, 4);
      expect(results.any((tm) => tm.name == "Sally"), false);
      expect(results.any((tm) => tm.name == "Kanye"), false);
    });
  });

  group("whereBeginsWith matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereBeginsWith("B");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Bob");

      q = new Query<TestModel>()..where["name"] = whereNot(whereBeginsWith("B"));
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Bob"), false);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereBeginsWith("b", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Bob");

      q = new Query<TestModel>()..where["name"] = whereNot(whereBeginsWith("b", caseSensitive: false));
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Bob"), false);
    });
  });

  group("whereEndsWith matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereEndsWith("m");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Tim");

      q = new Query<TestModel>()..where["name"] = whereNot(whereEndsWith("m"));
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Tim"), false);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereEndsWith("M", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Tim");

      q = new Query<TestModel>()..where["name"] = whereNot(whereEndsWith("M", caseSensitive: false));
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Tim"), false);
    });
  });

  ////

  group("whereDoesNotContain matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotContain("y");
      var results = await q.fetch();
      expect(results.length, 4);
      expect(results.any((t) => t.name == "Sally"), false);
      expect(results.any((t) => t.name == "Kanye"), false);

      q = new Query<TestModel>()..where["name"] = whereNot(whereDoesNotContain("y"));
      results = await q.fetch();
      expect(results.length, 2);
      expect(results.any((t) => t.name == "Sally"), true);
      expect(results.any((t) => t.name == "Kanye"), true);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotContain("Y", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 4);
      expect(results.any((t) => t.name == "Sally"), false);
      expect(results.any((t) => t.name == "Kanye"), false);

      q = new Query<TestModel>()..where["name"] = whereNot(whereDoesNotContain("Y", caseSensitive: false));
      results = await q.fetch();
      expect(results.length, 2);
      expect(results.any((t) => t.name == "Sally"), true);
      expect(results.any((t) => t.name == "Kanye"), true);
    });
  });

  group("whereDoesNotBeginWith With matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotBeginWith("B");
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.name == "Bob"), false);

      q = new Query<TestModel>()..where["name"] = whereNot(whereDoesNotBeginWith("B"));
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.name == "Bob"), true);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotBeginWith("b", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.name == "Bob"), false);

      q = new Query<TestModel>()..where["name"] = whereNot(whereDoesNotBeginWith("b", caseSensitive: false));
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.name == "Bob"), true);
    });
  });

  group("whereDoesNotEndWith matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotEndWith("m");
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.name == "Tim"), false);

      q = new Query<TestModel>()..where["name"] = whereNot(whereDoesNotEndWith("m"));
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.name == "Tim"), true);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotEndWith("M", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.name == "Tim"), false);

      q = new Query<TestModel>()..where["name"] = whereNot(whereDoesNotEndWith("M", caseSensitive: false));
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.name == "Tim"), true);
    });
  });

}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @managedPrimaryKey
  int id;

  String name;

  @ManagedColumnAttributes(nullable: true, unique: true)
  String email;

  InnerModel inner;
}

class InnerModel extends ManagedObject<_InnerModel> implements _InnerModel {}

class _InnerModel {
  @managedPrimaryKey
  int id;

  String name;

  @ManagedRelationship(#inner)
  TestModel owner;
}
