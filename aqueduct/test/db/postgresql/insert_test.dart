import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  ManagedContext context;

  tearDown(() async {
    await context?.close();
    context = null;
  });

  test("Accessing valueObject of Query automatically creates an instance",
      () async {
    context = await contextWithModels([TestModel]);

    var q = Query<TestModel>(context)..values.id = 1;

    expect(q.values.id, 1);
  });

  test("May set values to null, but the query will fail", () async {
    context = await contextWithModels([TestModel]);

    final q = Query<TestModel>(context);
    q.values = null;

    try {
      await q.insert();
      fail('unreachable');
    } on QueryException catch (e) {
      expect(e.message, contains("non_null_violation"));
    }
  });

  test(
      "Setting a non-null value to null will identify offending column in response",
      () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = null
      ..emailAddress = "dup@a.com";

    final q = Query<TestModel>(context)..values = m;

    try {
      await q.insert();
      fail('unreachable');
    } on QueryException catch (e) {
      expect(e.message, contains("non_null_violation"));
      expect(e.response.body["detail"], contains("simple.name"));
    }
  });

  test("Insert Bad Key", () async {
    context = await contextWithModels([TestModel]);

    var insertReq = Query<TestModel>(context)
      ..valueMap = {
        "name": "bob",
        "emailAddress": "bk@a.com",
        "bad_key": "doesntmatter"
      };

    try {
      await insertReq.insert();
      expect(true, false);
    } on ArgumentError catch (e) {
      expect(e.toString(),
          contains("Column 'bad_key' does not exist for table 'simple'"));
    }
  });

  test("Insert from static method", () async {
    context = await contextWithModels([TestModel]);
    final o = await Query.insertObject(context, TestModel()..name = "Bob");
    expect(o.id, isNotNull);
    expect(o.name, "Bob");
  });

  test("Inserting an object that violated a unique constraint fails", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "bob"
      ..emailAddress = "dup@a.com";

    var insertReq = Query<TestModel>(context)..values = m;
    await insertReq.insert();

    var insertReqDup = Query<TestModel>(context)..values = m;

    var successful = false;
    try {
      await insertReqDup.insert();
      successful = true;
    } on QueryException catch (e) {
      expect(e.event, QueryExceptionEvent.conflict);
      expect((e.underlyingException as PostgreSQLException).code, "23505");
    }
    expect(successful, false);

    m.emailAddress = "dup1@a.com";
    var insertReqFollowup = Query<TestModel>(context)..values = m;

    var result = await insertReqFollowup.insert();

    expect(result.emailAddress, "dup1@a.com");
  });

  test(
      "Insert an object that violates a unique set constraint fails with conflict",
      () async {
    context = await contextWithModels([MultiUnique]);

    var q = Query<MultiUnique>(context)
      ..values.a = "a"
      ..values.b = "b";

    await q.insert();

    q = Query<MultiUnique>(context)
      ..values.a = "a"
      ..values.b = "a";

    await q.insert();

    q = Query<MultiUnique>(context)
      ..values.a = "a"
      ..values.b = "b";
    try {
      await q.insert();
      expect(true, false);
    } on QueryException catch (e) {
      expect(e.event, QueryExceptionEvent.conflict);
    }
  });

  test("Inserting an object works and returns the object", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "bob"
      ..emailAddress = "1@a.com";

    var insertReq = Query<TestModel>(context)..values = m;

    var result = await insertReq.insert();

    expect(result is TestModel, true);
    expect(result.id, greaterThan(0));
    expect(result.name, "bob");
    expect(result.emailAddress, "1@a.com");
  });

  test("Inserting multiple objects works and returns the objects", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "bob"
      ..emailAddress = "1@a.com";

    var n = TestModel()
      ..name = "jay"
      ..emailAddress = "2@a.com";

    final models = await Query.insertObjects(context, [m, n]);
    final bob = models[0];
    final jay = models[1];

    expect(bob is TestModel, true);
    expect(bob.id, greaterThan(0));
    expect(bob.name, "bob");
    expect(bob.emailAddress, "1@a.com");

    expect(jay is TestModel, true);
    expect(jay.id, greaterThan(0));
    expect(jay.name, "jay");
    expect(jay.emailAddress, "2@a.com");
  });

  test(
      "Inserting multiple objects with at least one bad one does not insert any objects into the database",
      () async {
    context = await contextWithModels([TestModel]);

    var goodModel = TestModel()
      ..name = "bob"
      ..emailAddress = "1@a.com";

    var badModel = TestModel()
      ..name = null
      ..emailAddress = "2@a.com";

    try {
      await Query.insertObjects(context, [goodModel, badModel]);
      fail("unreachable");
    } catch (e) {
      expect(e, isNotNull);
    }

    final insertedModels = await Query<TestModel>(context).fetch();
    expect(insertedModels.length, isZero);
  });

  test("Inserting an object works", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()
      ..name = "bob"
      ..emailAddress = "2@a.com";

    var insertReq = Query<TestModel>(context)..values = m;

    var result = await insertReq.insert();

    var readReq = Query<TestModel>(context)
      ..predicate =
          QueryPredicate("emailAddress = @email", {"email": "2@a.com"});

    result = await readReq.fetchOne();
    expect(result.name, "bob");
  });

  test("Inserting an object without required key fails", () async {
    context = await contextWithModels([TestModel]);

    var m = TestModel()..emailAddress = "required@a.com";

    var insertReq = Query<TestModel>(context)..values = m;

    var successful = false;
    try {
      await insertReq.insert();
      successful = true;
    } on QueryException catch (e) {
      expect(e.event, QueryExceptionEvent.input);
      expect((e.underlyingException as PostgreSQLException).code, "23502");
    }
    expect(successful, false);
  });

  test(
      "Inserting an object via a values map works and returns appropriate object",
      () async {
    context = await contextWithModels([TestModel]);

    var insertReq = Query<TestModel>(context)
      ..valueMap = {"id": 20, "name": "Bob"}
      ..returningProperties((t) => [t.id, t.name]);

    var value = await insertReq.insert();
    expect(value.id, 20);
    expect(value.name, "Bob");
    expect(value.asMap().containsKey("emailAddress"), false);

    insertReq = Query<TestModel>(context)
      ..valueMap = {"id": 21, "name": "Bob"}
      ..returningProperties((t) => [t.id, t.name, t.emailAddress]);

    value = await insertReq.insert();
    expect(value.id, 21);
    expect(value.name, "Bob");
    expect(value.emailAddress, null);
    expect(value.asMap().containsKey("emailAddress"), true);
    expect(value.asMap()["emailAddress"], null);
  });

  test("Inserting object with relationship returns embedded object", () async {
    context = await contextWithModels([GenUser, GenPost]);

    var u = GenUser()..name = "Joe";
    var q = Query<GenUser>(context)..values = u;
    u = await q.insert();

    var p = GenPost()
      ..owner = u
      ..text = "1";
    var pq = Query<GenPost>(context)..values = p;
    p = await pq.insert();

    expect(p.id, greaterThan(0));
    expect(p.owner.id, greaterThan(0));
  });

  test("Timestamp inserted correctly by default", () async {
    context = await contextWithModels([GenTime]);

    var t = GenTime()..text = "hey";

    var q = Query<GenTime>(context)..values = t;

    var result = await q.insert();

    expect(result.dateCreated is DateTime, true);
    expect(result.dateCreated.difference(DateTime.now()).inSeconds <= 0, true);
  });

  test("Can insert timestamp manually", () async {
    context = await contextWithModels([GenTime]);

    var dt = DateTime.now();
    var t = GenTime()
      ..dateCreated = dt
      ..text = "hey";

    var q = Query<GenTime>(context)..values = t;

    var result = await q.insert();

    expect(result.dateCreated is DateTime, true);
    expect(result.dateCreated.difference(dt).inSeconds == 0, true);
  });

  test("Transient values work correctly", () async {
    context = await contextWithModels([TransientModel]);

    var t = TransientModel()..value = "foo";

    var q = Query<TransientModel>(context)..values = t;
    var result = await q.insert();
    expect(result.transientValue, null);
  });

  test("JSON -> Insert with List", () async {
    context = await contextWithModels([GenUser, GenPost]);

    var json = {
      "name": "Bob",
      "posts": [
        {"text": "Post"}
      ]
    };

    var u = GenUser()..readFromMap(json);

    var q = Query<GenUser>(context)..values = u;

    var result = await q.insert();
    expect(result.id, greaterThan(0));
    expect(result.name, "Bob");
    expect(result.posts, isNull);

    var pq = Query<GenPost>(context);
    expect(await pq.fetch(), hasLength(0));
  });

  test("Insert object with no keys", () async {
    context = await contextWithModels([BoringObject]);

    var q = Query<BoringObject>(context);
    var result = await q.insert();
    expect(result.id, greaterThan(0));
  });

  test("Can use insert private properties", () async {
    context = await contextWithModels([PrivateField]);

    await (Query<PrivateField>(context)..values.public = "abc").insert();
    var q = Query<PrivateField>(context);
    var result = await q.fetch();
    expect(result.first.public, "abc");
  });

  test("Can use enum to set property to be stored in db", () async {
    context = await contextWithModels([EnumObject]);

    var q = Query<EnumObject>(context)..values.enumValues = EnumValues.efgh;

    var result = await q.insert();
    expect(result.enumValues, EnumValues.efgh);
  });

  test("Can insert enum value that is null", () async {
    context = await contextWithModels([EnumObject]);

    var q = Query<EnumObject>(context)..values.enumValues = null;

    var result = await q.insert();
    expect(result.enumValues, isNull);
  });

  test("Can infer query from values in constructor", () async {
    context = await contextWithModels([TestModel]);

    final tm = TestModel()
      ..id = 1
      ..name = "Fred";
    final q = Query(context, values: tm);
    final t = await q.insert();
    expect(t.id, 1);
    expect(t.name, "Fred");
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int id;

  String name;

  @Column(nullable: true, unique: true)
  String emailAddress;

  static String tableName() {
    return "simple";
  }
}

class GenUser extends ManagedObject<_GenUser> implements _GenUser {}

class _GenUser {
  @primaryKey
  int id;
  String name;

  ManagedSet<GenPost> posts;
}

class GenPost extends ManagedObject<_GenPost> implements _GenPost {}

class _GenPost {
  @primaryKey
  int id;
  String text;

  @Relate(Symbol('posts'))
  GenUser owner;
}

class GenTime extends ManagedObject<_GenTime> implements _GenTime {}

class _GenTime {
  @primaryKey
  int id;

  String text;

  @Column(defaultValue: "(now() at time zone 'utc')")
  DateTime dateCreated;
}

class TransientModel extends ManagedObject<_Transient> implements _Transient {
  @Serialize()
  String transientValue;
}

class _Transient {
  @primaryKey
  int id;

  String value;
}

class BoringObject extends ManagedObject<_BoringObject>
    implements _BoringObject {}

class _BoringObject {
  @primaryKey
  int id;
}

class PrivateField extends ManagedObject<_PrivateField>
    implements _PrivateField {
  set public(String p) {
    _private = p;
  }

  String get public => _private;
}

class _PrivateField {
  @primaryKey
  int id;

  String _private;
}

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}

class _EnumObject {
  @primaryKey
  int id;

  @Column(nullable: true)
  EnumValues enumValues;
}

class MultiUnique extends ManagedObject<_MultiUnique> implements _MultiUnique {}

@Table.unique([Symbol('a'), Symbol('b')])
class _MultiUnique {
  @primaryKey
  int id;

  String a;
  String b;
}

enum EnumValues { abcd, efgh, other18 }
