import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ManagedContext context = null;

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
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where["email"] = whereEqualTo("0@a.com");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = new Query<TestModel>()..where["email"] = whereEqualTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 0);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where["email"] = whereEqualTo("0@A.com", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);
    });
  });


  test("Less than matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereLessThan(3);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results.first.id, 1);
    expect(results.last.id, 2);
  });

  test("Less than equal to matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereLessThanEqualTo(3);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 2);
    expect(results[2].id, 3);
  });

  test("Greater than matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereGreaterThan(4);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 5);
    expect(results[1].id, 6);
  });

  test("Greater than equal to matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereGreaterThanEqualTo(4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 4);
    expect(results[1].id, 5);
    expect(results[2].id, 6);
  });

  group("Not equal matcher", () {
    test("Non-string value", () async {
      var q = new Query<TestModel>()..where["id"] = whereNotEqualTo(1);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where["email"] = whereNotEqualTo("0@a.com");
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = new Query<TestModel>()..where["email"] = whereNotEqualTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 6);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where["email"] = whereNotEqualTo("0@A.com", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);
    });
  });


  test("whereIn matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereIn([1, 2]);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 1);
    expect(results[1].id, 2);

    // Now as iterable
    var iter = [1, 2].map((i) => i);
    q = new Query<TestModel>()..where["id"] = whereIn(iter);
    results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 1);
    expect(results[1].id, 2);
  });

  test("whereBetween matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereBetween(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);
  });

  test("whereOutsideOf matcher", () async {
    var q = new Query<TestModel>()..where["id"] = whereOutsideOf(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 5);
    expect(results[2].id, 6);
  });

  test("whereRelatedByValue matcher", () async {
    var q = new Query<InnerModel>()..where["owner"] = whereRelatedByValue(1);
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.owner.id, 1);
  });

  test("whereNull matcher", () async {
    var q = new Query<InnerModel>()..where["owner"] = whereNull;
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "No one's");
  });

  test("whereNotNull matcher", () async {
    var q = new Query<InnerModel>()..where["owner"] = whereNotNull;
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob's");
  });

  test("whereAnyMatch matcher", () async {
    var q = new Query<TestModel>()..joinOne((t) => t.inner);
    var results = await q.fetch();
    expect(results.length, 6);

    expect(results.first.name, "Bob");
    expect(results.first.inner.name, "Bob's");

    for (var i = 1; i < results.length; i++) {
      expect(results[i].inner, isNull);
    }
  });

  group("whereContains matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereContainsString("y");
      var results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.name, "Sally");
      expect(results.last.name, "Kanye");
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereContainsString("Y", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.name, "Sally");
      expect(results.last.name, "Kanye");
    });
  });

  group("whereBeginsWith matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereBeginsWith("B");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Bob");
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereBeginsWith("b", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Bob");
    });
  });

  group("whereEndsWith matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereEndsWith("m");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Tim");
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereEndsWith("M", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Tim");
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
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotContain("Y", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 4);
      expect(results.any((t) => t.name == "Sally"), false);
      expect(results.any((t) => t.name == "Kanye"), false);
    });
  });

  group("whereDoesNotBeginWith With matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotBeginWith("B");
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.name == "Bob"), false);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotBeginWith("b", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.name == "Bob"), false);
    });
  });

  group("whereDoesNotEndWith matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotEndWith("m");
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.name == "Tim"), false);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where["name"] = whereDoesNotEndWith("M", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.name == "Tim"), false);
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
