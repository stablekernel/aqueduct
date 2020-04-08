import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  ManagedContext context;

  tearDown(() async {
    await context?.close();
    context = null;
  });

  test("Updating existing object works", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = Query<TestModel>(context)..values = m;
    await req.insert();

    m
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    req = Query<TestModel>(context)
      ..predicate = QueryPredicate("name = @name", {"name": "Bob"})
      ..values = m;

    var response = await req.update();
    var result = response.first;

    expect(result.name, "Fred");
    expect(result.emailAddress, "2@a.com");
  });

  test(
      "Updating non-nullable property to null gives error that specifies the offending property",
      () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = Query<TestModel>(context)..values = m;
    await req.insert();

    m
      ..name = null
      ..emailAddress = "2@a.com";

    req = Query<TestModel>(context)
      ..predicate = QueryPredicate("name = @name", {"name": "Bob"})
      ..values = m;

    try {
      await req.update();
      fail('unreachable');
    } on QueryException catch (e) {
      expect(e.message, contains("non_null_violation"));
      expect(e.response.body["detail"], contains("_testmodel.name"));
    }
  });

  test("Setting relationship to a new value succeeds", () async {
    context = await contextWithModels([Child, Parent]);

    var q = Query<Parent>(context)..values.name = "Bob";
    var parent = await q.insert();

    var childQuery = Query<Child>(context)
      ..values.name = "Fred"
      ..values.parent = parent;

    var child = await childQuery.insert();
    expect(child.parent.id, parent.id);

    q = Query<Parent>(context)..values.name = "Sally";
    var newParent = await q.insert();

    childQuery = Query<Child>(context)
      ..where((o) => o.id).equalTo(child.id)
      ..values.parent = newParent;
    child = (await childQuery.update()).first;
    expect(child.parent.id, newParent.id);
  });

  test("Setting relationship to null succeeds", () async {
    context = await contextWithModels([Child, Parent]);

    var parent = Parent()..name = "Bob";
    var q = Query<Parent>(context)..values = parent;
    parent = await q.insert();

    var child = Child()
      ..name = "Fred"
      ..parent = parent;
    var childQuery = Query<Child>(context)..values = child;
    child = await childQuery.insert();
    expect(child.parent.id, parent.id);

    childQuery = Query<Child>(context)
      ..where((o) => o.id).equalTo(child.id)
      ..values = (Child()..parent = null);
    child = (await childQuery.update()).first;
    expect(child.parent, isNull);
  });

  test("Updating non-existent object does nothing", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = Query<TestModel>(context)..values = m;
    await req.insert();

    m
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    req = Query<TestModel>(context)
      ..predicate = QueryPredicate("name = @name", {"name": "John"})
      ..values = m;

    var response = await req.update();
    expect(response.length, 0);

    req = Query<TestModel>(context);
    var fetchResponse = await req.fetchOne();
    expect(fetchResponse.name, "Bob");
    expect(fetchResponse.emailAddress, "1@a.com");
  });

  test("Update object with ModelQuery", () async {
    context = await contextWithModels([TestModel]);

    var m1 = TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = Query<TestModel>(context)..values = m1;
    m1 = await req.insert();

    var m2 = TestModel()
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    req = Query<TestModel>(context)..values = m2;
    await req.insert();

    var q = Query<TestModel>(context)
      ..where((o) => o.name).equalTo("Bob")
      ..values = (TestModel()..emailAddress = "3@a.com");

    List<TestModel> results = await q.update();
    expect(results, hasLength(1));
    expect(results.first.id, m1.id);
    expect(results.first.emailAddress, "3@a.com");
    expect(results.first.name, "Bob");
  });

  test("Update object with new value for column in predicate", () async {
    context = await contextWithModels([TestModel]);
    var m1 = TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    m1 = await (Query<TestModel>(context)..values = m1).insert();

    await (Query<TestModel>(context)
          ..values = (TestModel()
            ..name = "Fred"
            ..emailAddress = "2@a.com"))
        .insert();

    var updateQuery = Query<TestModel>(context)
      ..where((o) => o.emailAddress).equalTo("1@a.com")
      ..values.emailAddress = "3@a.com";
    var updatedObject = (await updateQuery.update()).first;

    expect(updatedObject.emailAddress, "3@a.com");

    var allUsers = await Query<TestModel>(context).fetch();
    expect(allUsers.length, 2);
    expect(allUsers.firstWhere((m) => m.id == m1.id).emailAddress, "3@a.com");
    expect(allUsers.firstWhere((m) => m.id != m1.id).emailAddress, "2@a.com");
  });

  test("updateOne returns updated object if found, null if not", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = Query<TestModel>(context)..values = m;
    await req.insert();

    req = Query<TestModel>(context)
      ..predicate = QueryPredicate("name = @name", {"name": "Bob"})
      ..values.name = "John";

    var response = await req.updateOne();
    expect(response.name, "John");
    expect(response.emailAddress, "1@a.com");

    req = Query<TestModel>(context)
      ..predicate = QueryPredicate("name = @name", {"name": "Bob"})
      ..values.name = "John";

    response = await req.updateOne();
    expect(response, isNull);
  });

  test("updateOne throws exception if it updated more than one object",
      () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";
    var fred = TestModel()
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    var req = Query<TestModel>(context)..values = m;
    await req.insert();
    req = Query<TestModel>(context)..values = fred;
    await req.insert();

    req = Query<TestModel>(context)
      ..predicate = QueryPredicate("name is not null", null)
      ..values.name = "Joe";

    try {
      var _ = await req.updateOne();
      expect(true, false);
    } on StateError catch (e) {
      expect(e.toString(),
          contains("'updateOne' modified more than one row in '_TestModel'"));
    }
  });

  test("Update all without safeguard fails", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";
    var fred = TestModel()
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    var req = Query<TestModel>(context)..values = m;
    await req.insert();
    req = Query<TestModel>(context)..values = fred;
    await req.insert();

    req = Query<TestModel>(context)..values.name = "Joe";

    try {
      var _ = await req.update();
      expect(true, false);
    } on StateError catch (e) {
      expect(
          e.message,
          contains(
              "Query is either update or delete query with no WHERE clause"));
    }
  });

  test("Update all WITH safeguard succeeds", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";
    var fred = TestModel()
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    var req = Query<TestModel>(context)..values = m;
    await req.insert();
    req = Query<TestModel>(context)..values = fred;
    await req.insert();

    req = Query<TestModel>(context)
      ..canModifyAllInstances = true
      ..values.name = "Fred";

    var res = await req.update();
    expect(res.map((tm) => tm.name), everyElement("Fred"));
  });

  test(
      "Attempted update that will cause conflict throws appropriate QueryException",
      () async {
    context = await contextWithModels([TestModel]);

    var objects = [
      TestModel()
        ..name = "Bob"
        ..emailAddress = "1@a.com",
      TestModel()
        ..name = "Fred"
        ..emailAddress = "2@a.com"
    ];
    for (var o in objects) {
      var req = Query<TestModel>(context)..values = o;
      await req.insert();
    }

    try {
      var q = Query<TestModel>(context)
        ..where((o) => o.emailAddress).equalTo("2@a.com")
        ..values.emailAddress = "1@a.com";
      await q.updateOne();
      expect(true, false);
    } on QueryException catch (e) {
      expect(e.event, QueryExceptionEvent.conflict);
    }
  });

  test("Can use enum to set property to be stored in db", () async {
    context = await contextWithModels([EnumObject]);

    var q = Query<EnumObject>(context)..values.enumValues = EnumValues.efgh;

    await q.insert();

    q = Query<EnumObject>(context)..values.enumValues = EnumValues.abcd;

    await q.insert();

    q = Query<EnumObject>(context)
      ..values.enumValues = EnumValues.other18Letters
      ..where((o) => o.enumValues).equalTo(EnumValues.efgh);

    var result = await q.update();
    expect(result.length, 1);
    expect(result.first.enumValues, EnumValues.other18Letters);
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int id;

  String name;

  @Column(nullable: true, unique: true)
  String emailAddress;
}

class Child extends ManagedObject<_Child> implements _Child {}

class _Child {
  @primaryKey
  int id;

  String name;

  @Relate(Symbol('child'), isRequired: false, onDelete: DeleteRule.cascade)
  Parent parent;
}

class Parent extends ManagedObject<_Parent> implements _Child {}

class _Parent {
  @primaryKey
  int id;

  String name;

  Child child;
}

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}

class _EnumObject {
  @primaryKey
  int id;

  EnumValues enumValues;
}

enum EnumValues { abcd, efgh, other18Letters }
