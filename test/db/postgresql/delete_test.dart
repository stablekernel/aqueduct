import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'package:postgresql/postgresql.dart' as postgresql;

void main() {
  PostgresModelAdapter adapter;

  setUp(() {
    adapter = new PostgresModelAdapter(null, () async {
      var uri = 'postgres://dart:dart@localhost:5432/dart_test';
      return await postgresql.connect(uri);
    });
  });

  tearDown(() {
    adapter.close();
    adapter = null;
  });

  test("Deleting an object works", () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    var m = new TestModel()
      ..email = "a@a.com"
      ..name = "joe";
    var req = new Query<TestModel>()..valueObject = m;

    TestModel inserted = await req.insert(adapter);
    expect(inserted.id, greaterThan(0));

    req = new Query<TestModel>()
      ..predicate = new Predicate("id = @id", {"id": inserted.id});

    var count = await req.delete(adapter);
    expect(count, 1);

    req = new Query<TestModel>()
      ..predicate = new Predicate("id = @id", {"id": inserted.id});

    var result = await req.fetch(adapter);

    expect(result.length, 0);
  });

  test("Deleting all objects works", () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel()
        ..email = "${i}@a.com"
        ..name = "joe";

      var req = new Query<TestModel>()..valueObject = m;

      await req.insert(adapter);
    }

    var req = new Query<TestModel>();
    var result = await req.fetch(adapter);
    expect(result.length, 10);

    req = new Query<TestModel>();
    var count = await req.delete(adapter);
    expect(count, 10);

    req = new Query<TestModel>();
    result = await req.fetch(adapter);
    expect(result.length, 0);
  });

  test("Deleting a related object w/nullify sets property to null", () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel, RefModel]);

    var obj = new TestModel()..name = "a";
    var req = new Query<TestModel>()..valueObject = obj;
    var testObj = await req.insert(adapter);

    obj = new RefModel()..test = testObj;
    req = new Query<RefModel>()..valueObject = obj;
    var refObj = await req.insert(adapter);

    req = new Query<TestModel>();
    var count = await req.delete(adapter);
    expect(count, 1);

    req = new Query<RefModel>()..resultKeys = ["id", "test"];
    refObj = await req.fetchOne(adapter);
    expect(refObj.test, null);
  });

  test("Deleting a related object w/restrict fails", () async {
    await generateTemporarySchemaFromModels(
        adapter, [GRestrict, GRestrictInverse]);

    var obj = new GRestrictInverse()..name = "a";
    var req = new Query<GRestrictInverse>()..valueObject = obj;
    var testObj = await req.insert(adapter);

    obj = new GRestrict()..test = testObj;
    req = new Query<GRestrict>()..valueObject = obj;
    await req.insert(adapter);

    try {
      req = new Query<GRestrictInverse>();
      await req.delete(adapter);
      fail("Should not be able to delete object");
    } catch (e) {
      expect(e.statusCode, 400);
      expect(e.errorCode, 23503);
    }
  });

  test("Deleting cascade object deletes other object", () async {
    await generateTemporarySchemaFromModels(
        adapter, [GCascade, GCascadeInverse]);

    var obj = new GCascadeInverse()..name = "a";
    var req = new Query<GCascadeInverse>()..valueObject = obj;
    var testObj = await req.insert(adapter);

    obj = new GCascade()..test = testObj;
    req = new Query<GCascade>()..valueObject = obj;
    await req.insert(adapter);

    req = new Query<GCascadeInverse>();
    var count = await req.delete(adapter);
    expect(count, 1);

    req = new Query<GCascade>();
    var res = await req.fetch(adapter);
    expect(res.length, 0);
  });
}

@ModelBacking(TestModelBacking)
@proxy
class TestModel extends Model implements TestModelBacking {
}

class TestModelBacking {
  @Attributes(primaryKey: true, databaseType: "bigserial")
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

@ModelBacking(RefModelBacking)
@proxy
class RefModel extends Model implements RefModelBacking {

}

class RefModelBacking {
  @Attributes(primaryKey: true, databaseType: "serial")
  int id;

  @Attributes(nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "ref",
      deleteRule: RelationshipDeleteRule.nullify)
  TestModel test;
}

@ModelBacking(GRestrictInverseBacking) @proxy
class GRestrictInverse extends Model implements GRestrictInverseBacking {

}

class GRestrictInverseBacking {
  @Attributes(primaryKey: true, databaseType: "serial")
  int id;

  String name;

  @RelationshipAttribute(RelationshipType.hasMany, "test")
  GRestrict test;
}

@ModelBacking(GRestrictBacking) @proxy
class GRestrict extends Model implements GRestrictBacking {

}

class GRestrictBacking {
  @Attributes(primaryKey: true, databaseType: "serial")
  int id;

  @Attributes(nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "test",
      deleteRule: RelationshipDeleteRule.restrict)
  GRestrictInverse test;
}

@ModelBacking(GCascadeInverseBacking) @proxy
class GCascadeInverse extends Model implements GCascadeInverseBacking {

}

class GCascadeInverseBacking {
  @Attributes(primaryKey: true, databaseType: "serial")
  int id;

  String name;

  @RelationshipAttribute(RelationshipType.hasMany, "test")
  GCascade test;
}

@ModelBacking(GCascadeBacking) @proxy
class GCascade extends Model implements GCascadeBacking {

}

class GCascadeBacking {
  @Attributes(primaryKey: true, databaseType: "serial")
  int id;

  @Attributes(nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "test",
      deleteRule: RelationshipDeleteRule.cascade)
  GCascadeInverse test;
}
