import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  ManagedContext context;

  setUpAll(() async {
    context = await contextWithModels([TestModel, InnerModel]);
    var counter = 0;
    var names = ["Bob", "Fred", "Tim", "Sally", "Kanye", "Lisa"];
    for (var name in names) {
      var q = Query<TestModel>(context)
        ..values.name = name
        ..values.email = "$counter@a.com";
      await q.insert();

      counter++;
    }

    var q = Query<InnerModel>(context)
      ..values.name = "Bob's"
      ..values.owner = (TestModel()..id = 1);
    await q.insert();

    q = Query<InnerModel>(context)..values.name = "No one's";
    await q.insert();
  });

  tearDownAll(() async {
    await context?.close();
    context = null;
  });

  group("Equals matcher", () {
    test("Non-string value", () async {
      var q = Query<TestModel>(context)..where((p) => p.id).equalTo(1);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = Query<TestModel>(context)..where((p) => p.id).not.equalTo(1);

      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.id == 1), false);
    });

    test("String value, case sensitive default", () async {
      var q = Query<TestModel>(context)
        ..where((o) => o.email).equalTo("0@a.com");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.equalTo("0@a.com");
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.id == 1), false);

      q = Query<TestModel>(context)..where((o) => o.email).equalTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.equalTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)..where((o) => o.email).equalTo("%.com");
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)..where((o) => o.email).not.equalTo("%.com");
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)..where((o) => o.email).equalTo("\\%.com");
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.equalTo("\\%.com");
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)..where((o) => o.email).equalTo("_@a.com");
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.equalTo("_@a.com");
      results = await q.fetch();
      expect(results.length, 6);
    });

    test("String value, case insensitive default", () async {
      var q = Query<TestModel>(context)
        ..where((o) => o.email).equalTo("0@A.com", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.equalTo("0@A.com", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.email == "0@a.com"), false);

      q = Query<TestModel>(context)..where((o) => o.email).equalTo("%.COM");
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)..where((o) => o.email).not.equalTo("%.COM");
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)..where((o) => o.email).equalTo("\\%.COM");
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.equalTo("\\%.COM");
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)..where((o) => o.email).equalTo("_@a.COM");
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.equalTo("_@a.COM");
      results = await q.fetch();
      expect(results.length, 6);
    });
  });

  group("Like matcher", () {
    test("case sensitive default", () async {
      var q = Query<TestModel>(context)..where((o) => o.email).like("0@a%");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = Query<TestModel>(context)..where((o) => o.email).not.like("0@a%");
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.id == 1), false);

      q = Query<TestModel>(context)..where((o) => o.email).like("0@A%");
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)..where((o) => o.email).not.like("0@A%");
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)..where((o) => o.email).like("%.com");
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)..where((o) => o.email).not.like("%.com");
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)..where((o) => o.email).like("_@a.com");
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)..where((o) => o.email).not.like("_@a.com");
      results = await q.fetch();
      expect(results.length, 0);
    });

    test("case insensitive default", () async {
      var q = Query<TestModel>(context)
        ..where((o) => o.email).like("0@A%", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.like("0@A%", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.email == "0@a.com"), false);

      q = Query<TestModel>(context)
        ..where((o) => o.email).like("%.COM", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.like("%.COM", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 0);

      q = Query<TestModel>(context)
        ..where((o) => o.email).like("_@a.COM", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.like("_@a.COM", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 0);
    });
  });

  test("Less than matcher", () async {
    var q = Query<TestModel>(context)..where((o) => o.id).lessThan(3);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results.first.id, 1);
    expect(results.last.id, 2);

    q = Query<TestModel>(context)..where((o) => o.id).not.lessThan(3);
    results = await q.fetch();
    expect(results.length, 4);
    expect(results.every((tm) => tm.id >= 3), true);
  });

  test("Less than equal to matcher", () async {
    var q = Query<TestModel>(context)..where((o) => o.id).lessThanEqualTo(3);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 2);
    expect(results[2].id, 3);

    q = Query<TestModel>(context)..where((o) => o.id).not.lessThanEqualTo(3);
    results = await q.fetch();
    expect(results.length, 3);
    expect(results.every((tm) => tm.id > 3), true);
  });

  test("Greater than matcher", () async {
    var q = Query<TestModel>(context)..where((o) => o.id).greaterThan(4);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 5);
    expect(results[1].id, 6);

    q = Query<TestModel>(context)..where((o) => o.id).not.greaterThan(4);
    results = await q.fetch();
    expect(results.length, 4);
    expect(results.every((tm) => tm.id <= 4), true);
  });

  test("Greater than equal to matcher", () async {
    var q = Query<TestModel>(context)..where((o) => o.id).greaterThanEqualTo(4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 4);
    expect(results[1].id, 5);
    expect(results[2].id, 6);

    q = Query<TestModel>(context)..where((o) => o.id).not.greaterThanEqualTo(4);
    results = await q.fetch();
    expect(results.length, 3);
    expect(results.every((tm) => tm.id < 4), true);
  });

  group("Not equal matcher", () {
    test("Non-string value", () async {
      var q = Query<TestModel>(context)..where((o) => o.id).notEqualTo(1);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = Query<TestModel>(context)..where((o) => o.id).not.notEqualTo(1);
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.id == 1), true);
    });

    test("String value, case sensitive default", () async {
      var q = Query<TestModel>(context)
        ..where((o) => o.email).notEqualTo("0@a.com");
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.notEqualTo("0@a.com");
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.id == 1), true);

      q = Query<TestModel>(context)
        ..where((o) => o.email).notEqualTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 6);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.notEqualTo("0@A.com");
      results = await q.fetch();
      expect(results.length, 0);
    });

    test("String value, case sensitive default", () async {
      var q = Query<TestModel>(context)
        ..where((o) => o.email).notEqualTo("0@A.com", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((t) => t.id == 1), false);

      q = Query<TestModel>(context)
        ..where((o) => o.email).not.notEqualTo("0@A.com", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 1);
      expect(results.any((t) => t.id == 1), true);
    });
  });

  test("oneOf matcher", () async {
    var q = Query<TestModel>(context)..where((o) => o.id).oneOf([1, 2]);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 1);
    expect(results[1].id, 2);

    q = Query<TestModel>(context)..where((o) => o.id).not.oneOf([1, 2]);
    results = await q.fetch();
    expect(results.length, 4);
    expect(results.any((t) => t.id == 1), false);
    expect(results.any((t) => t.id == 2), false);

    try {
      Query<TestModel>(context).where((o) => o.id).not.oneOf([]);
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("oneOf' cannot be the empty set or null"));
    }
  });

  test("whereBetween matcher", () async {
    var q = Query<TestModel>(context)..where((o) => o.id).between(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);

    q = Query<TestModel>(context)..where((o) => o.id).not.between(2, 4);
    results = await q.fetch();
    expect(results.length, 3);

    results.sort((t1, t2) => t1.id.compareTo(t2.id));
    expect(results[0].id, 1);
    expect(results[1].id, 5);
    expect(results[2].id, 6);
  });

  test("whereOutsideOf matcher", () async {
    var q = Query<TestModel>(context)..where((o) => o.id).outsideOf(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 5);
    expect(results[2].id, 6);

    q = Query<TestModel>(context)..where((o) => o.id).not.outsideOf(2, 4);
    results = await q.fetch();
    expect(results.length, 3);

    results.sort((t1, t2) => t1.id.compareTo(t2.id));
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);
  });

  test("identifiedBy matcher", () async {
    var q = Query<InnerModel>(context)..where((o) => o.owner).identifiedBy(1);
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.owner.id, 1);

    // Does not include null values; this is intentional.
    q = Query<InnerModel>(context)..where((o) => o.owner).not.identifiedBy(1);
    results = await q.fetch();
    expect(results.length, 0);
  });

  test("whereNull matcher", () async {
    var q = Query<InnerModel>(context)..where((o) => o.owner).isNull();
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "No one's");

    q = Query<InnerModel>(context)..where((o) => o.owner).not.isNull();
    results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob's");
  });

  test("whereNotNull matcher", () async {
    var q = Query<InnerModel>(context)..where((o) => o.owner).isNotNull();
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob's");

    q = Query<InnerModel>(context)..where((o) => o.owner).not.isNotNull();
    results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "No one's");
  });

  group("whereContains matcher", () {
    test("Case sensitive, default", () async {
      var q = Query<TestModel>(context)..where((o) => o.name).contains("y");
      var results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.name, "Sally");
      expect(results.last.name, "Kanye");

      q = Query<TestModel>(context)..where((o) => o.name).not.contains("y");
      results = await q.fetch();
      expect(results.length, 4);
      expect(results.any((tm) => tm.name == "Sally"), false);
      expect(results.any((tm) => tm.name == "Kanye"), false);
    });

    test("Case insensitive", () async {
      var q = Query<TestModel>(context)
        ..where((o) => o.name).contains("Y", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.name, "Sally");
      expect(results.last.name, "Kanye");

      q = Query<TestModel>(context)
        ..where((o) => o.name).not.contains("Y", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 4);
      expect(results.any((tm) => tm.name == "Sally"), false);
      expect(results.any((tm) => tm.name == "Kanye"), false);
    });
  });

  group("whereBeginsWith matcher", () {
    test("Case sensitive, default", () async {
      var q = Query<TestModel>(context)..where((o) => o.name).beginsWith("B");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Bob");

      q = Query<TestModel>(context)..where((o) => o.name).not.beginsWith("B");
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Bob"), false);
    });

    test("Case insensitive", () async {
      var q = Query<TestModel>(context)
        ..where((o) => o.name).beginsWith("b", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Bob");

      q = Query<TestModel>(context)
        ..where((o) => o.name).not.beginsWith("b", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Bob"), false);
    });
  });

  group("whereEndsWith matcher", () {
    test("Case sensitive, default", () async {
      var q = Query<TestModel>(context)..where((o) => o.name).endsWith("m");
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Tim");

      q = Query<TestModel>(context)..where((o) => o.name).not.endsWith("m");
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Tim"), false);
    });

    test("Case insensitive", () async {
      var q = Query<TestModel>(context)
        ..where((o) => o.name).endsWith("M", caseSensitive: false);
      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.name, "Tim");

      q = Query<TestModel>(context)
        ..where((o) => o.name).not.endsWith("M", caseSensitive: false);
      results = await q.fetch();
      expect(results.length, 5);
      expect(results.any((tm) => tm.name == "Tim"), false);
    });
  });

  group("not matcher", () {
    test("can invert back to identity", () async {
      var q = Query<TestModel>(context)..where((o) => o.id).not.not.equalTo(1);
      final results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.id, 1);
    });
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

  @Relate(Symbol('inner'))
  TestModel owner;
}
