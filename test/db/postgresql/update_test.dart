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

    var req = new Query<TestModel>()..values = m;
    await req.insert();

    m
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    req = new Query<TestModel>()
      ..predicate = new Predicate("name = @name", {"name": "Bob"})
      ..values = m;

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
      ..values = parent;
    parent = await q.insert();

    var child = new Child()
      ..name = "Fred"
      ..parent = parent;
    q = new Query<Child>()
      ..values = child;
    child = await q.insert();
    expect(child.parent.id, parent.id);

    q = new ModelQuery<Child>()
      ..["id"] = whereEqualTo(child.id)
      ..values = (new Child()..parent = null);
    child = (await q.update()).first;
    expect(child.parent, isNull);
  });

  test("Updating non-existent object does nothing", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = new Query<TestModel>()..values = m;
    await req.insert();

    m
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    req = new Query<TestModel>()
      ..predicate = new Predicate("name = @name", {"name": "John"})
      ..values = m;

    var response = await req.update();
    expect(response.length, 0);

    req = new Query<TestModel>();
    response = await req.fetchOne();
    expect(response.name, "Bob");
    expect(response.emailAddress, "1@a.com");
  });

  test("Update object with ModelQuery", () async {
    context = await contextWithModels([TestModel]);

    var m1 = new TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = new Query<TestModel>()..values = m1;
    m1 = await req.insert();

    var m2 = new TestModel()
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    req = new Query<TestModel>()..values = m2;
    await req.insert();

    var q = new ModelQuery<TestModel>()
      ..["name"] = "Bob"
      ..values = (new TestModel()..emailAddress = "3@a.com");

    List<TestModel> results = await q.update();
    expect(results, hasLength(1));
    expect(results.first.id, m1.id);
    expect(results.first.emailAddress, "3@a.com");
    expect(results.first.name, "Bob");

  });

  test("Update object with new value for column in predicate", () async {
    context = await contextWithModels([TestModel]);
    var m1 = new TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    m1 = await (new Query<TestModel>()..values = m1).insert();

    await (new Query<TestModel>()
      ..values = (new TestModel()
        ..name = "Fred"
        ..emailAddress = "2@a.com")).insert();

    var updateQuery = new ModelQuery<TestModel>()
      ..["emailAddress"] = "1@a.com"
      ..values.emailAddress = "3@a.com";
    var updatedObject = (await updateQuery.update()).first;

    expect(updatedObject.emailAddress, "3@a.com");

    var allUsers = await (new Query<TestModel>()).fetch();
    expect(allUsers.length, 2);
    expect(allUsers.firstWhere((m) => m.id == m1.id).emailAddress, "3@a.com");
    expect(allUsers.firstWhere((m) => m.id != m1.id).emailAddress, "2@a.com");
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

