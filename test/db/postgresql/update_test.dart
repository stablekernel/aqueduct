import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ModelContext context = null;

  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Updating existing object works", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = new Query<TestModel>()..valueObject = m;
    await req.insert();

    m
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    req = new Query<TestModel>()
      ..predicate = new Predicate("name = @name", {"name": "Bob"})
      ..valueObject = m;

    var response = await req.update();
    var result = response.first;

    expect(result.name, "Fred");
    expect(result.emailAddress, "2@a.com");
  });

  test("Setting relationship to null succeeds", () async {
    context = await contextWithModels([Child, Parent]);

    var parent = new Parent()
      ..name = "Bob";
    var q = new Query<Parent>()
      ..valueObject = parent;
    parent = await q.insert();

    var child = new Child()
      ..name = "Fred"
      ..parent = parent;
    q = new Query<Child>()
      ..valueObject = child;
    child = await q.insert();
    expect(child.parent.id, parent.id);

    fail("Find a new place for this");
//    var matcher = new ModelQuery<Child>()
//      ..["id"] = whereEqualTo(child.id);
//    q = new Query<Child>()
//      ..predicate = matcher.predicate
//      ..valueObject = (new Child()..parent = null);
//    child = (await q.update()).first;
//    expect(child.parent, isNull);

  });

  test("Updating non-existent object fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = new Query<TestModel>()..valueObject = m;
    await req.insert();

    m
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    req = new Query<TestModel>()
      ..predicate = new Predicate("name = @name", {"name": "John"})
      ..valueObject = m;

    var response = await req.update();
    expect(response.length, 0);

    req = new Query<TestModel>();
    response = await req.fetchOne();
    expect(response.name, "Bob");
    expect(response.emailAddress, "1@a.com");

  });
}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;

  @Attributes(nullable: true, unique: true)
  String emailAddress;
}

class Child extends Model<_Child> implements _Child {}
class _Child {
  @primaryKey
  int id;

  String name;

  @RelationshipAttribute(RelationshipType.belongsTo, "child", required: false, deleteRule: RelationshipDeleteRule.cascade)
  Parent parent;
}

class Parent extends Model<_Parent> implements _Child {}
class _Parent {
  @primaryKey
  int id;

  String name;

  @RelationshipAttribute(RelationshipType.hasOne, "parent")
  Child child;
}

