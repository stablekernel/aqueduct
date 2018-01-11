import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';
import '../../helpers.dart';

void main() {
  ManagedContext context;

  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Deleting an object works", () async {
    context = await contextWithModels([TestModel, RefModel]);

    var m = new TestModel()
      ..email = "a@a.com"
      ..name = "joe";
    var req = new Query<TestModel>()..values = m;

    var inserted = await req.insert();
    expect(inserted.id, greaterThan(0));

    req = new Query<TestModel>()
      ..predicate = new QueryPredicate("id = @id", {"id": inserted.id});

    var count = await req.delete();
    expect(count, 1);

    req = new Query<TestModel>()
      ..predicate = new QueryPredicate("id = @id", {"id": inserted.id});

    var result = await req.fetch();

    expect(result.length, 0);
  });

  test("Deleting an object when there are many only deletes that object",
      () async {
    context = await contextWithModels([TestModel, RefModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel()
        ..email = "$i@a.com"
        ..name = "joe";

      var req = new Query<TestModel>()..values = m;

      await req.insert();
    }

    var req = new Query<TestModel>();
    var result = await req.fetch();
    expect(result.length, 10);

    req = new Query<TestModel>()
      ..predicate = new QueryPredicate("id = @id", {"id": 1});
    var count = await req.delete();
    expect(count, 1);

    req = new Query<TestModel>();
    result = await req.fetch();
    expect(result.length, 9);
  });

  test("Deleting all objects works, as long as you specify the magic",
      () async {
    context = await contextWithModels([TestModel, RefModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel()
        ..email = "$i@a.com"
        ..name = "joe";

      var req = new Query<TestModel>()..values = m;

      await req.insert();
    }

    var req = new Query<TestModel>();
    var result = await req.fetch();
    expect(result.length, 10);

    req = new Query<TestModel>()..canModifyAllInstances = true;
    var count = await req.delete();
    expect(count, 10);

    req = new Query<TestModel>();
    result = await req.fetch();
    expect(result.length, 0);
  });

  test("Trying to delete all objects without specifying the magic fails",
      () async {
    context = await contextWithModels([TestModel, RefModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel()
        ..email = "$i@a.com"
        ..name = "joe";

      var req = new Query<TestModel>()..values = m;

      await req.insert();
    }

    var req = new Query<TestModel>();
    var result = await req.fetch();
    expect(result.length, 10);

    try {
      req = new Query<TestModel>();
      await req.delete();
    } on StateError catch (e) {
      expect(e.toString(), contains("'canModifyAllInstances'"));
    }

    req = new Query<TestModel>();
    result = await req.fetch();
    expect(result.length, 10);
  });

  test("Deleting a related object w/nullify sets property to null", () async {
    context = await contextWithModels([TestModel, RefModel]);

    var testModelObject = new TestModel()..name = "a";
    var testModelReq = new Query<TestModel>()..values = testModelObject;
    var testObj = await testModelReq.insert();

    var refModelObject = new RefModel()..test = testObj;
    var refModelReq = new Query<RefModel>()..values = refModelObject;
    var refObj = await refModelReq.insert();

    testModelReq = new Query<TestModel>()..canModifyAllInstances = true;
    var count = await testModelReq.delete();
    expect(count, 1);

    refModelReq = new Query<RefModel>()
      ..returningProperties((r) => [r.id, r.test]);
    refObj = await refModelReq.fetchOne();
    expect(refObj.test, null);
  });

  test("Deleting a related object w/restrict fails", () async {
    context = await contextWithModels([GRestrict, GRestrictInverse]);

    var griObject = new GRestrictInverse()..name = "a";
    var griReq = new Query<GRestrictInverse>()..values = griObject;
    var testObj = await griReq.insert();

    var grObject = new GRestrict()..test = testObj;
    var grReq = new Query<GRestrict>()..values = grObject;
    await grReq.insert();

    var successful = false;
    try {
      griReq = new Query<GRestrictInverse>()..canModifyAllInstances = true;
      await griReq.delete();
      successful = true;
    } on QueryException catch (e) {
      expect(e.event, QueryExceptionEvent.input);
      expect((e.underlyingException as PostgreSQLException).code, "23503");
    }
    expect(successful, false);
  });

  test("Deleting cascade object deletes other object", () async {
    context = await contextWithModels([GCascade, GCascadeInverse]);

    var obj = new GCascadeInverse()..name = "a";
    var req = new Query<GCascadeInverse>()..values = obj;
    var testObj = await req.insert();

    var cascadeObj = new GCascade()..test = testObj;
    var cascadeReq = new Query<GCascade>()..values = cascadeObj;
    await cascadeReq.insert();

    req = new Query<GCascadeInverse>()..canModifyAllInstances = true;
    var count = await req.delete();
    expect(count, 1);

    cascadeReq = new Query<GCascade>();
    var res = await cascadeReq.fetch();
    expect(res.length, 0);
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int id;

  String name;

  @Column(nullable: true, unique: true)
  String email;

  ManagedSet<RefModel> ref;

  static String tableName() {
    return "simple";
  }

  @override
  String toString() {
    return "TestModel: $id $name $email";
  }
}

class RefModel extends ManagedObject<_RefModel> implements _RefModel {}

class _RefModel {
  @primaryKey
  int id;

  @Relate(#ref,
      isRequired: false, onDelete: DeleteRule.nullify)
  TestModel test;
}

class GRestrictInverse extends ManagedObject<_GRestrictInverse>
    implements _GRestrictInverse {}

class _GRestrictInverse {
  @primaryKey
  int id;

  String name;

  ManagedSet<GRestrict> test;
}

class GRestrict extends ManagedObject<_GRestrict> implements _GRestrict {}

class _GRestrict {
  @primaryKey
  int id;

  @Relate(#test,
      isRequired: false, onDelete: DeleteRule.restrict)
  GRestrictInverse test;
}

class GCascadeInverse extends ManagedObject<_GCascadeInverse>
    implements _GCascadeInverse {}

class _GCascadeInverse {
  @primaryKey
  int id;

  String name;

  ManagedSet<GCascade> test;
}

class GCascade extends ManagedObject<_GCascade> implements _GCascade {}

class _GCascade {
  @primaryKey
  int id;

  @Relate(#test,
      isRequired: false, onDelete: DeleteRule.cascade)
  GCascadeInverse test;
}
