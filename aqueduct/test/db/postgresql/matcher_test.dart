import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ManagedContext context;

  setUpAll(() async {
    context = await contextWithModels([TestModel, InnerModel, AnotherTestModel]);
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
    });

    test("String value, case sensitive default", () async {
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

  group("Or Where", () {
    justLogEverything();

    setUpAll(() async {
      var realBob = Query<AnotherTestModel>(context)
        ..values.name = "Bob"
        ..values.email = "founder@company.com"
        ..values.rank = "8000";
      await realBob.insert();

      var alsoRealBob = Query<AnotherTestModel>(context)
        ..values.name = "Bob"
        ..values.email = "bob@company.com"
        ..values.rank = "9999";
      await alsoRealBob.insert();

      var decoyDude = Query<AnotherTestModel>(context)
        ..values.name = "The Dude"
        ..values.email = "bowling@alley.com"
        ..values.rank = '1';
      await decoyDude.insert();

      var imposterBob = Query<AnotherTestModel>(context)
        ..values.name = "Bob"
        ..values.email = "contractor@company.com"
        ..values.rank = "8000";
      await imposterBob.insert();

      var anotherImposterBob = Query<AnotherTestModel>(context)
        ..values.name = "Bob"
        ..values.email = "bobby@company.com"
        ..values.rank = "100";
      await anotherImposterBob.insert();

      var cofounder = Query<AnotherTestModel>(context)
        ..values.name = "Jeff"
        ..values.email = "founder@company.com"
        ..values.rank = "9998";
      await cofounder.insert();

      var imposterCoFounder = Query<AnotherTestModel>(context)
        ..values.name = "Jeff"
        ..values.email = "intern@company.com"
        ..values.rank = "2";
      await imposterCoFounder.insert();
    });

    test("simple Or", () async {
      //select * from users where name = 'Bob' and (email = "ceo@company.com" or rank > 9000)

      var r = Query<AnotherTestModel>(context)
        ..where((o) => o.email).equalTo("founder@company.com")
        ..orWhere((o) => o.rank).greaterThan("9000")
        ..sortBy((r) => r.name, QuerySortOrder.ascending);

      var results = await r.fetch();

      expect(results.length, 3);

      final firstResult = results[0];
      expect(firstResult.name, "Bob");
      expect(firstResult.email, "founder@company.com");
      expect(firstResult.rank, "8000");

      final secondResult = results[1];
      expect(secondResult.name, "Bob");
      expect(secondResult.email, "bob@company.com");
      expect(secondResult.rank, "9999");

      final thirdResult = results[2];
      expect(thirdResult.name, "Jeff");
      expect(thirdResult.email, "founder@company.com");
      expect(thirdResult.rank, "9998");
    });

    test("And Or", () async {
      // SELECT id,name,rank,email FROM _AnotherTestModel
      // WHERE _AnotherTestModel.rank > @_AnotherTestModel_rank:text AND _AnotherTestModel.name LIKE @_AnotherTestModel_name:text OR _AnotherTestModel.email LIKE @_AnotherTestModel_email:text

      var r1 = Query<AnotherTestModel>(context)
        ..where((o) => o.email).equalTo("founder@company.com")
        ..where((o) => o.name).equalTo("Bob")
        ..orWhere((o) => o.rank).equalTo("9999")
        ..sortBy((r) => r.name, QuerySortOrder.ascending);

      var results1 = await r1.fetch();

      expect(results1.length, 2);

      final firstResult1 = results1[0];
      expect(firstResult1.name, "Bob");
      expect(firstResult1.email, "founder@company.com");
      expect(firstResult1.rank, "8000");

      final secondResult1 = results1[1];
      expect(secondResult1.name, "Bob");
      expect(secondResult1.email, "bob@company.com");
      expect(secondResult1.rank, "9999");

      var r2 = Query<AnotherTestModel>(context)
        ..where((o) => o.email).equalTo("founder@company.com")
        ..orWhere((o) => o.rank).equalTo("9999") //switching these
        ..where((o) => o.name).equalTo("Bob")    // switching these
        ..sortBy((r) => r.name, QuerySortOrder.ascending);

      var results2 = await r2.fetch();

      expect(results2.length, 3);

      final firstResult2 = results2[0];
      expect(firstResult2.name, "Bob");
      expect(firstResult2.email, "founder@company.com");
      expect(firstResult2.rank, "8000");

      final secondResult2 = results2[1];
      expect(secondResult2.name, "Bob");
      expect(secondResult2.email, "bob@company.com");
      expect(secondResult2.rank, "9999");

      final thirdResult2 = results2[2];
      expect(thirdResult2.name, "Jeff");
      expect(thirdResult2.email, "founder@company.com");
      expect(thirdResult2.rank, "9998");
    });

    test("Complex And Or", () async {
      // SELECT id,name,rank,email FROM _AnotherTestModel
      // WHERE _AnotherTestModel.name LIKE @_AnotherTestModel_name:text AND _AnotherTestModel.email LIKE @_AnotherTestModel_email:text OR _AnotherTestModel.rank > @_AnotherTestModel_rank:text AND _AnotherTestModel.name LIKE @_AnotherTestModel_name0:text
      // ORDER BY _AnotherTestModel.name ASC

      var r = Query<AnotherTestModel>(context)
        ..where((o) => o.name).equalTo("Bob")
        ..where((o) => o.email).equalTo("founder@company.com")
        ..orWhere((o) => o.rank).greaterThan("9000")
        ..where((o) => o.name).equalTo("Bob")
        ..sortBy((r) => r.name, QuerySortOrder.ascending);

      var results1 = await r.fetch();

      expect(results1.length, 2);

      final firstResult = results1[0];
      expect(firstResult.name, "Bob");
      expect(firstResult.email, "founder@company.com");
      expect(firstResult.rank, "8000");

      final secondResult = results1[1];
      expect(secondResult.name, "Bob");
      expect(secondResult.email, "bob@company.com");
      expect(secondResult.rank, "9999");
    });

    test("whereGroup (implicit and)", () async {
      // SELECT id,name,rank,email FROM _AnotherTestModel WHERE (_AnotherTestModel.name LIKE @_AnotherTestModel_name:text AND ((_AnotherTestModel.email LIKE @_AnotherTestModel_email:text OR _AnotherTestModel.rank > @_AnotherTestModel_rank:text)))   Substitutes: {_AnotherTestModel_name: Bob, _AnotherTestModel_email: ceo@company.com, _AnotherTestModel_rank: 9000} -> [[1, Bob, 8000, ceo@company.com], [2, Bob, 9999, bob@company.com]] null null

      var r = Query<AnotherTestModel>(context)
        ..where((o) => o.email).equalTo("founder@company.com")
        ..whereGroup((query) => query
            ..where((o) => o.name).equalTo("Bob")
            ..orWhere((o) => o.name).equalTo("Jeff"))
      ..sortBy((r) => r.name, QuerySortOrder.ascending);

      var results= await r.fetch();

      expect(results.length, 3);

      final firstResult = results[0];
      expect(firstResult.name, "Bob");
      expect(firstResult.email, "founder@company.com");
      expect(firstResult.rank, "8000");

      final secondResult = results[1];
      expect(secondResult.name, "Jeff");
      expect(secondResult.email, "founder@company.com");
      expect(secondResult.rank, "9998");

      final thirdResult = results[2];
      expect(thirdResult.name, "Jeff");
      expect(thirdResult.email, "intern@company.com");
      expect(thirdResult.rank, "2");
    });

    test("orWhereGroup", () async {
      // SELECT id,name,rank,email FROM _AnotherTestModel
      // WHERE (_AnotherTestModel.email LIKE @_AnotherTestModel_email:text OR (_AnotherTestModel.name LIKE @_AnotherTestModel_name:text AND _AnotherTestModel.rank > @_AnotherTestModel_rank:text))
      var r = Query<AnotherTestModel>(context)
        ..where((o) => o.email).equalTo("founder@company.com")
        ..orWhereGroup((query) => query
          ..where((o) => o.name).equalTo("Bob")
          ..where((o) => o.rank).greaterThan("9000"))
        ..sortBy((r) => r.name, QuerySortOrder.ascending);

      var results = await r.fetch();

      expect(results.length, 3);

      final firstResult = results[0];
      expect(firstResult.name, "Bob");
      expect(firstResult.email, "founder@company.com");
      expect(firstResult.rank, "8000");

      final secondResult = results[1];
      expect(secondResult.name, "Bob");
      expect(secondResult.email, "bob@company.com");
      expect(secondResult.rank, "9999");

      final thirdResult = results[2];
      expect(thirdResult.name, "Jeff");
      expect(thirdResult.email, "founder@company.com");
      expect(thirdResult.rank, "9998");
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

class AnotherTestModel extends ManagedObject<_AnotherTestModel>
    implements _AnotherTestModel {}

class _AnotherTestModel {
  @primaryKey
  int id;

  String name;
  String rank;

  @Column(nullable: true, unique: false)
  String email;
}
