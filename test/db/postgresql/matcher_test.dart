import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ModelContext context = null;

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

    q = new Query<InnerModel>()
      ..values.name = "No one's";
    await q.insert();
  });

  tearDownAll(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Equals matcher", () async {
    var q = new Query<TestModel>()
        ..matchOn["id"] = whereEqualTo(1);
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.id, 1);
  });

  test("Less than matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["id"] = whereLessThan(3);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results.first.id, 1);
    expect(results.last.id, 2);
  });

  test("Less than equal to matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["id"] = whereLessThanEqualTo(3);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 2);
    expect(results[2].id, 3);
  });

  test("Greater than matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["id"] = whereGreaterThan(4);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 5);
    expect(results[1].id, 6);
  });

  test("Greater than equal to matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["id"] = whereGreaterThanEqualTo(4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 4);
    expect(results[1].id, 5);
    expect(results[2].id, 6);
  });

  test("Not equal to matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["id"] = whereNotEqual(1);
    var results = await q.fetch();
    expect(results.length, 5);
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);
    expect(results[3].id, 5);
    expect(results[4].id, 6);
  });

  test("whereIn matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["id"] = whereIn([1, 2]);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 1);
    expect(results[1].id, 2);

    // Now as iterable
    var iter = [1, 2].map((i) => i);
    q = new Query<TestModel>()
      ..matchOn["id"] = whereIn(iter);
    results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 1);
    expect(results[1].id, 2);
  });

  test("whereBetween matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["id"] = whereBetween(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);
  });

  test("whereOutsideOf matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["id"] = whereOutsideOf(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 5);
    expect(results[2].id, 6);
  });

  test("whereRelatedByValue matcher", () async {
    var q = new Query<InnerModel>()
      ..matchOn["owner"] = whereRelatedByValue(1);
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.owner.id, 1);
  });

  test("whereNull matcher", () async {
    var q = new Query<InnerModel>()
      ..matchOn["owner"] = whereNull;
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "No one's");
  });

  test("whereNotNull matcher", () async {
    var q = new Query<InnerModel>()
      ..matchOn["owner"] = whereNotNull;
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob's");
  });

  test("whereAnyMatch matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["inner"].includeInResultSet = true;
    var results = await q.fetch();
    expect(results.length, 6);

    expect(results.first.name, "Bob");
    expect(results.first.inner.name, "Bob's");

    for (var i = 1; i < results.length; i++) {
      expect(results[i].inner, isNull);
    }
  });

  test("whereContains matcher", () async {
    var q = new Query<TestModel>()
        ..matchOn["name"] = whereContains("y");
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results.first.name, "Sally");
    expect(results.last.name, "Kanye");
  });

  test("whereBeginsWith matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["name"] = whereBeginsWith("B");
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob");
  });

  test("whereEndsWith matcher", () async {
    var q = new Query<TestModel>()
      ..matchOn["name"] = whereEndsWith("m");
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Tim");
  });
}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;

  @AttributeHint(nullable: true, unique: true)
  String email;

  InnerModel inner;
}

class InnerModel extends Model<_InnerModel> implements _InnerModel {}
class _InnerModel {
  @primaryKey
  int id;

  String name;

  @RelationshipInverse(#inner)
  TestModel owner;
}