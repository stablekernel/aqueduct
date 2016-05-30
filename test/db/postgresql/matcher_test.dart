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
    var q = new ModelQuery<TestModel>()
        ..["id"] = whereEqualTo(1);
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.id, 1);
  });

  test("Less than matcher", () async {
    var q = new ModelQuery<TestModel>()
      ..["id"] = whereLessThan(3);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results.first.id, 1);
    expect(results.last.id, 2);
  });

  test("Less than equal to matcher", () async {
    var q = new ModelQuery<TestModel>()
      ..["id"] = whereLessThanEqualTo(3);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 2);
    expect(results[2].id, 3);
  });

  test("Greater than matcher", () async {
    var q = new ModelQuery<TestModel>()
      ..["id"] = whereGreaterThan(4);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 5);
    expect(results[1].id, 6);
  });

  test("Greater than equal to matcher", () async {
    var q = new ModelQuery<TestModel>()
      ..["id"] = whereGreaterThanEqualTo(4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 4);
    expect(results[1].id, 5);
    expect(results[2].id, 6);
  });

  test("Not equal to matcher", () async {
    var q = new ModelQuery<TestModel>()
      ..["id"] = whereNotEqual(1);
    var results = await q.fetch();
    expect(results.length, 5);
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);
    expect(results[3].id, 5);
    expect(results[4].id, 6);
  });

  test("whereIn matcher", () async {
    var q = new ModelQuery<TestModel>()
      ..["id"] = whereIn([1, 2]);
    var results = await q.fetch();
    expect(results.length, 2);
    expect(results[0].id, 1);
    expect(results[1].id, 2);
  });

  test("whereBetween matcher", () async {
    var q = new ModelQuery<TestModel>()
      ..["id"] = whereBetween(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 2);
    expect(results[1].id, 3);
    expect(results[2].id, 4);
  });

  test("whereOutsideOf matcher", () async {
    var q = new ModelQuery<TestModel>()
      ..["id"] = whereOutsideOf(2, 4);
    var results = await q.fetch();
    expect(results.length, 3);
    expect(results[0].id, 1);
    expect(results[1].id, 5);
    expect(results[2].id, 6);
  });

  test("whereRelatedByValue matcher", () async {
    var q = new ModelQuery<InnerModel>()
      ..["owner"] = whereRelatedByValue(1);
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.owner.id, 1);
  });

  test("whereNull matcher", () async {
    var q = new ModelQuery<InnerModel>()
      ..["owner"] = whereNull;
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "No one's");
  });

  test("whereNotNull matcher", () async {
    var q = new ModelQuery<InnerModel>()
      ..["owner"] = whereNotNull;
    var results = await q.fetch();
    expect(results.length, 1);
    expect(results.first.name, "Bob's");
  });

  test("whereAnyMatch matcher", () async {
    var q = new ModelQuery<TestModel>()
      ..["inner"] = whereAnyMatch;
    var results = await q.fetch();
    expect(results.length, 6);

    expect(results.first.name, "Bob");
    expect(results.first.inner.name, "Bob's");

    for (var i = 1; i < results.length; i++) {
      expect(results[i].inner, isNull);
    }

  });

}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;

  @Attributes(nullable: true, unique: true)
  String email;

  @RelationshipAttribute.hasOne("owner")
  InnerModel inner;
}

class InnerModel extends Model<_InnerModel> implements _InnerModel {}
class _InnerModel {
  @primaryKey
  int id;

  String name;

  @RelationshipAttribute.belongsTo("inner")
  TestModel owner;
}