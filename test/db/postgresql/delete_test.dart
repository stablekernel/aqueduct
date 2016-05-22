import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ModelContext context = null;

  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Deleting an object works", () async {
    context = await contextWithModels([TestModel, RefModel]);

    var m = new TestModel()
      ..email = "a@a.com"
      ..name = "joe";
    var req = new Query<TestModel>()..valueObject = m;

    var inserted = await req.insert();
    expect(inserted.id, greaterThan(0));

    req = new Query<TestModel>()
      ..predicate = new Predicate("id = @id", {"id": inserted.id});

    var count = await req.delete();
    expect(count, 1);

    req = new Query<TestModel>()
      ..predicate = new Predicate("id = @id", {"id": inserted.id});

    var result = await req.fetch();

    expect(result.length, 0);
  });

  test("Deleting an object when there are many only deletes that object", () async {
    context = await contextWithModels([TestModel, RefModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel()
        ..email = "${i}@a.com"
        ..name = "joe";

      var req = new Query<TestModel>()..valueObject = m;

      await req.insert();
    }

    var req = new Query<TestModel>();
    var result = await req.fetch();
    expect(result.length, 10);

    req = new Query<TestModel>()..predicate = new Predicate("id = @id", {"id" : 1});
    var count = await req.delete();
    expect(count, 1);

    req = new Query<TestModel>();
    result = await req.fetch();
    expect(result.length, 9);
  });

  test("Deleting all objects works", () async {
    context = await contextWithModels([TestModel, RefModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel()
        ..email = "${i}@a.com"
        ..name = "joe";

      var req = new Query<TestModel>()..valueObject = m;

      await req.insert();
    }

    var req = new Query<TestModel>();
    var result = await req.fetch();
    expect(result.length, 10);

    req = new Query<TestModel>();
    var count = await req.delete();
    expect(count, 10);

    req = new Query<TestModel>();
    result = await req.fetch();
    expect(result.length, 0);
  });

  test("Deleting a related object w/nullify sets property to null", () async {
    context = await contextWithModels([TestModel, RefModel]);

    var obj = new TestModel()..name = "a";
    var req = new Query<TestModel>()..valueObject = obj;
    var testObj = await req.insert();

    obj = new RefModel()..test = testObj;
    req = new Query<RefModel>()..valueObject = obj;
    var refObj = await req.insert();

    req = new Query<TestModel>();
    var count = await req.delete();
    expect(count, 1);

    req = new Query<RefModel>()..resultKeys = ["id", "test"];
    refObj = await req.fetchOne();
    expect(refObj.test, null);
  });

  test("Deleting a related object w/restrict fails", () async {
    context = await contextWithModels([GRestrict, GRestrictInverse]);

    var obj = new GRestrictInverse()..name = "a";
    var req = new Query<GRestrictInverse>()..valueObject = obj;
    var testObj = await req.insert();

    obj = new GRestrict()..test = testObj;
    req = new Query<GRestrict>()..valueObject = obj;
    await req.insert();

    var successful = false;
    try {
      req = new Query<GRestrictInverse>();
      await req.delete();
      successful = true;
    } catch (e) {
      expect(e.statusCode, 400);
      expect(e.errorCode, 23503);
    }
    expect(successful, false);
  });

  test("Deleting cascade object deletes other object", () async {
    context = await contextWithModels([GCascade, GCascadeInverse]);

    var obj = new GCascadeInverse()..name = "a";
    var req = new Query<GCascadeInverse>()..valueObject = obj;
    var testObj = await req.insert();

    obj = new GCascade()..test = testObj;
    req = new Query<GCascade>()..valueObject = obj;
    await req.insert();

    req = new Query<GCascadeInverse>();
    var count = await req.delete();
    expect(count, 1);

    req = new Query<GCascade>();
    var res = await req.fetch();
    expect(res.length, 0);
  });
}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;

  @Attributes(nullable: true, unique: true)
  String email;

  @RelationshipAttribute(RelationshipType.hasMany, "test")
  RefModel ref;

  static String tableName() {
    return "simple";
  }

  String toString() {
    return "TestModel: ${id} ${name} ${email}";
  }
}

class RefModel extends Model<_RefModel> implements _RefModel {}
class _RefModel {
  @primaryKey
  int id;

  @RelationshipAttribute(RelationshipType.belongsTo, "ref", required: false, deleteRule: RelationshipDeleteRule.nullify)
  TestModel test;
}

class GRestrictInverse extends Model<_GRestrictInverse> implements _GRestrictInverse {}
class _GRestrictInverse {
  @primaryKey
  int id;

  String name;

  @RelationshipAttribute(RelationshipType.hasMany, "test")
  GRestrict test;
}

class GRestrict extends Model<_GRestrict> implements _GRestrict {}

class _GRestrict {
  @primaryKey
  int id;

  @RelationshipAttribute(RelationshipType.belongsTo, "test", required: false, deleteRule: RelationshipDeleteRule.restrict)
  GRestrictInverse test;
}

class GCascadeInverse extends Model<_GCascadeInverse> implements _GCascadeInverse {}

class _GCascadeInverse {
  @primaryKey
  int id;

  String name;

  @RelationshipAttribute(RelationshipType.hasMany, "test")
  GCascade test;
}

class GCascade extends Model<_GCascade> implements _GCascade {}

class _GCascade {
  @primaryKey
  int id;

  @RelationshipAttribute(RelationshipType.belongsTo, "test", required: false, deleteRule: RelationshipDeleteRule.cascade)
  GCascadeInverse test;
}
