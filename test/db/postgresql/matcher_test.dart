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
      var q = new Query<TestModel>()..where((p) => p.id).equalTo(1);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = new Query<TestModel>()..where((p) => p.id).equalTo(1).invert();
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.id == 1), false);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where((o) => o.email).equalTo("0@a.com");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = new Query<TestModel>()..where((o) => o.email).equalTo("0@a.com").invert();
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.id == 1), false);

      q = new Query<TestModel>()..where((o) => o.email).equalTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 0);

      q = new Query<TestModel>()..where((o) => o.email).equalTo("0@A.com").invert();
      results = await q.fetch();
      expect(results.length, 6);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where((o) => o.email).equalTo("0@A.com", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = new Query<TestModel>()..where((o) => o.email).equalTo("0@A.com", caseSensitive: false).invert();
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.email == "0@a.com"), false);
    });
  });

  test("Less than matcher", () async {
    var q = new Query<TestModel>()..where((o) => o.id).lessThan(3);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results.first.id, 1);
    expect(results.last.id, 2);

    q = new Query<TestModel>()..where((o) => o.id).lessThan(3).invert();
    results = await q.fetch();
    expect(results.length, 4);
    expect(results.every((tm) => tm.id >= 3), true);
  });

  test("Less than equal to matcher", () async {
    var q = new Query<TestModel>()..where((o) => o.id).lessThanEqualTo(3);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 2);
    expect(results[2].id, 3);

    q = new Query<TestModel>()..where((o) => o.id).lessThanEqualTo(3).invert();
    results = await q.fetch();
    expect(results.length, 3);
    expect(results.every((tm) => tm.id > 3), true);
  });

  test("Greater than matcher", () async {
    var q = new Query<TestModel>()..where((o) => o.id).greaterThan(4);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 5);
    expect(results[1].id, 6);

    q = new Query<TestModel>()..where((o) => o.id).greaterThan(4).invert();
    results = await q.fetch();
    expect(results.length, 4);
    expect(results.every((tm) => tm.id <= 4), true);
  });

  test("Greater than equal to matcher", () async {
    var q = new Query<TestModel>()..where((o) => o.id).greaterThanEqualTo(4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 4);
    expect(results[1].id, 5);
    expect(results[2].id, 6);

    q = new Query<TestModel>()..where((o) => o.id).greaterThanEqualTo(4).invert();
    results = await q.fetch();
    expect(results.length, 3);
    expect(results.every((tm) => tm.id < 4), true);
  });

  group("Not equal matcher", () {
    test("Non-string value", () async {
      var q = new Query<TestModel>()..where((o) => o.id).notEqualTo(1);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = new Query<TestModel>()..where((o) => o.id).notEqualTo(1).invert();
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.id == 1), true);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where((o) => o.email).notEqualTo("0@a.com");
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = new Query<TestModel>()..where((o) => o.email).notEqualTo("0@a.com").invert();
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.id == 1), true);

      q = new Query<TestModel>()..where((o) => o.email).notEqualTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 6);

      q = new Query<TestModel>()..where((o) => o.email).notEqualTo("0@A.com").invert();
      results = await q.fetch();
      expect(results.length, 0);
    });

    test("String value, case sensitive default", () async {
      var q = new Query<TestModel>()..where((o) => o.email).notEqualTo("0@A.com", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = new Query<TestModel>()..where((o) => o.email).notEqualTo("0@A.com", caseSensitive: false).invert();
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.id == 1), true);
    });
  });

  test("whereIn matcher", () async {
    var q = new Query<TestModel>()..where((o) => o.id).oneOf([1, 2]);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 1);
    expect(results[1].id, 2);

    q = new Query<TestModel>()..where((o) => o.id).oneOf([1, 2]).invert();
    results = await q.fetch();
    expect(results.length, 4);
    expect(results.any((t) => t.id == 1), false);
    expect(results.any((t) => t.id == 2), false);
  });

  test("whereBetween matcher", () async {
    var q = new Query<TestModel>()..where((o) => o.id).between(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);

    q = new Query<TestModel>()..where((o) => o.id).between(2, 4).invert();
    results = await q.fetch();
    expect(results.length, 3);

    results.sort((t1, t2) => t1.id.compareTo(t2.id));
    expect(results[0].id, 1);
    expect(results[1].id, 5);
    expect(results[2].id, 6);
  });

  test("whereOutsideOf matcher", () async {
    var q = new Query<TestModel>()..where((o) => o.id).outsideOf(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 5);
    expect(results[2].id, 6);

    q = new Query<TestModel>()..where((o) => o.id).outsideOf(2, 4).invert();
    results = await q.fetch();
    expect(results.length, 3);

    results.sort((t1, t2) => t1.id.compareTo(t2.id));
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);
  });

  test("whereRelatedByValue matcher", () async {
    var q = new Query<InnerModel>()..where((o) => o.owner).relatedByValue(1);
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.owner.id, 1);

    // Does not include null values; this is intentional.
    q = new Query<InnerModel>()..where((o) => o.owner).relatedByValue(1).invert();
    results = await q.fetch();
    expect(results.length, 0);
  });

  test("whereNull matcher", () async {
    var q = new Query<InnerModel>()..where((o) => o.owner).isNull();
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "No one's");

    q = new Query<InnerModel>()..where((o) => o.owner).isNull().invert();
    results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob's");
  });

  test("whereNotNull matcher", () async {
    var q = new Query<InnerModel>()..where((o) => o.owner).isNotNull();
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob's");

    q = new Query<InnerModel>()..where((o) => o.owner).isNotNull().invert();
    results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "No one's");
  });

  group("whereContains matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where((o) => o.name).contains("y");
      var results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.name, "Sally");
      expect(results.last.name, "Kanye");

      q = new Query<TestModel>()..where((o) => o.name).contains("y").invert();
      results = await q.fetch();
      expect(results.length, 4);
      expect(results.any((tm) => tm.name == "Sally"), false);
      expect(results.any((tm) => tm.name == "Kanye"), false);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where((o) => o.name).contains("Y", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.name, "Sally");
      expect(results.last.name, "Kanye");

      q = new Query<TestModel>()..where((o) => o.name).contains("Y", caseSensitive: false).invert();
      results = await q.fetch();
      expect(results.length, 4);
      expect(results.any((tm) => tm.name == "Sally"), false);
      expect(results.any((tm) => tm.name == "Kanye"), false);
    });
  });

  group("whereBeginsWith matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where((o) => o.name).beginsWith("B");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Bob");

      q = new Query<TestModel>()..where((o) => o.name).beginsWith("B").invert();
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Bob"), false);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where((o) => o.name).beginsWith("b", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Bob");

      q = new Query<TestModel>()..where((o) => o.name).beginsWith("b", caseSensitive: false).invert();
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Bob"), false);
    });
  });

  group("whereEndsWith matcher", () {
    test("Case sensitive, default", () async {
      var q = new Query<TestModel>()..where((o) => o.name).endsWith("m");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Tim");

      q = new Query<TestModel>()..where((o) => o.name).endsWith("m").invert();
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Tim"), false);
    });

    test("Case insensitive", () async {
      var q = new Query<TestModel>()..where((o) => o.name).endsWith("M", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Tim");

      q = new Query<TestModel>()..where((o) => o.name).endsWith("M", caseSensitive: false).invert();
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Tim"), false);
    });
  });

  test("Apply expression directly to relationship fails", () {
    try {
      new Query<TestModel>()..where((t) => t.inner);
      fail("unreachable");
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Cannot select has-one or has-many"));
    }
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int id;

  String name;

  @Column(nullable: true, unique: true)
  String email;

  InnerModel inner;
}

class InnerModel extends ManagedObject<_InnerModel> implements _InnerModel {}

class _InnerModel {
  @primaryKey
  int id;

  String name;

  @Relate(#inner)
  TestModel owner;
}
