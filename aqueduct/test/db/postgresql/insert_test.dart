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

  test("Accessing values to a `Query` automatically creates an instance.",
      () async {
    context = await contextWithModels([TestModel]);

    var q = Query<TestModel>(context)..values.id = 1;

    expect(q.values.id, 1);
  });

  group("Method insert() in `Query`", () {
    test(
        "fails when values is set to `null` and the model has required fields.",
        () async {
      context = await contextWithModels([TestModel]);

      final q = Query<TestModel>(context);
      q.values = null;

      try {
        await q.insert();
        fail('should not be reached');
      } on QueryException catch (e) {
        expectNullViolation(e, columnName: "simple.name");
      }
    });

    test("fails when no value is set for a required field.", () async {
      context = await contextWithModels([TestModel]);

      var m = TestModel()..emailAddress = "required@a.com";

      var insertReq = Query<TestModel>(context)..values = m;

      try {
        await insertReq.insert();
        fail('should not be reached');
      } on QueryException catch (e) {
        expectNullViolation(e, columnName: "simple.name");
      }
    });

    test("fails when `null` is set as a value for a required field.", () async {
      context = await contextWithModels([TestModel]);

      var m = TestModel()
        ..name = null
        ..emailAddress = "dup@a.com";

      final q = Query<TestModel>(context)..values = m;

      try {
        await q.insert();
        fail('should not be reached');
      } on QueryException catch (e) {
        expectNullViolation(e, columnName: "simple.name");
      }
    });

    test("fails when a non-existent value is set to the `valueMap`.", () async {
      context = await contextWithModels([TestModel]);

      var insertReq = Query<TestModel>(context)
        ..valueMap = {
          "name": "bob",
          "emailAddress": "bk@a.com",
          "bad_key": "doesntmatter"
        };

      try {
        await insertReq.insert();
        fail('should not be reached');
      } on ArgumentError catch (e) {
        expect(e.toString(),
            contains("Column 'bad_key' does not exist for table 'simple'"));
      }
    });

    test("fails when an object that violated a unique constraint is inserted.",
        () async {
      context = await contextWithModels([TestModel]);

      var m = TestModel()
        ..name = "bob"
        ..emailAddress = "dup@a.com";

      var insertReq = Query<TestModel>(context)..values = m;
      await insertReq.insert();

      var insertReqDup = Query<TestModel>(context)..values = m;

      try {
        await insertReqDup.insert();
        fail('should not be reached');
      } on QueryException catch (e) {
        expectUniqueViolation(e);
      }

      m.emailAddress = "dup1@a.com";
      var insertReqFollowup = Query<TestModel>(context)..values = m;

      var result = await insertReqFollowup.insert();

      expect(result.emailAddress, "dup1@a.com");
    });

    test(
        "fails when an object that violates a unique set constraint is inserted.",
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
        fail('should not be reached');
      } on QueryException catch (e) {
        expectUniqueViolation(e);
      }
    });

    test("works given an object and returns is as a result.", () async {
      context = await contextWithModels([TestModel]);

      var m = TestModel()
        ..name = "bob"
        ..emailAddress = "1@a.com";

      var insertReq = Query<TestModel>(context)..values = m;

      var result = await insertReq.insert();

      expect(result, isA<TestModel>());
      expect(result.id, greaterThan(0));
      expect(result.name, "bob");
      expect(result.emailAddress, "1@a.com");
    });

    test("works given an object into the database.", () async {
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

    test("works when values are set directly to the `valueMap`.", () async {
      context = await contextWithModels([TestModel]);

      var insertReq = Query<TestModel>(context)
        ..valueMap = {"id": 20, "name": "Bob"}
        ..returningProperties((t) => [t.id, t.name]);

      var value = await insertReq.insert();
      expect(value.id, 20);
      expect(value.name, "Bob");
      expect(value.asMap(), doesNotContain("emailAddress"));

      insertReq = Query<TestModel>(context)
        ..valueMap = {"id": 21, "name": "Bob"}
        ..returningProperties((t) => [t.id, t.name, t.emailAddress]);

      value = await insertReq.insert();
      expect(value.id, 21);
      expect(value.name, "Bob");
      expect(value.emailAddress, isNull);
      expect(value.asMap(), containsPair("emailAddress", isNull));
    });

    test(
        "works when given object with relationship and returns embedded object.",
        () async {
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

    test("works correctly on an object with a default value for timestamp.",
        () async {
      context = await contextWithModels([GenTime]);

      var t = GenTime()..text = "hey";

      var q = Query<GenTime>(context)..values = t;

      var result = await q.insert();

      expect(result.dateCreated, isA<DateTime>());
      expect(result.dateCreated.difference(DateTime.now()).inMilliseconds,
          closeTo(0, 100));
    });

    test("works when timestamp is set manually.", () async {
      context = await contextWithModels([GenTime]);

      var dt = DateTime.now();
      var t = GenTime()
        ..dateCreated = dt
        ..text = "hey";

      var q = Query<GenTime>(context)..values = t;

      var result = await q.insert();

      expect(result.dateCreated, isA<DateTime>());
      expect(result.dateCreated.difference(dt).inMilliseconds, 0);
    });

    test("works properly given a model with transient value.", () async {
      context = await contextWithModels([TransientModel]);

      var t = TransientModel()..value = "foo";

      var q = Query<TransientModel>(context)..values = t;
      var result = await q.insert();
      expect(result.transientValue, isNull);
    });

    test("works when values are read from JSON and does not insert relations.",
        () async {
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

    test("works given an object with no keys.", () async {
      context = await contextWithModels([BoringObject]);

      var q = Query<BoringObject>(context);
      var result = await q.insert();
      expect(result.id, greaterThan(0));
    });

    test("works given an object with private fields.", () async {
      context = await contextWithModels([PrivateField]);

      await (Query<PrivateField>(context)..values.public = "abc").insert();
      var q = Query<PrivateField>(context);
      var result = await q.fetch();
      expect(result.first.public, "abc");
    });

    test("works when an enum is set as a value for enum field.", () async {
      context = await contextWithModels([EnumObject]);

      var q = Query<EnumObject>(context)..values.enumValues = EnumValues.efgh;

      var result = await q.insert();
      expect(result.enumValues, EnumValues.efgh);
    });

    test("works when an enum field is set to `null`.", () async {
      context = await contextWithModels([EnumObject]);

      var q = Query<EnumObject>(context)..values.enumValues = null;

      var result = await q.insert();
      expect(result.enumValues, isNull);
    });

    test("can infer query generic parameter from values in constructor.",
        () async {
      context = await contextWithModels([TestModel]);

      final tm = TestModel()
        ..id = 1
        ..name = "Fred";
      final q = Query(context, values: tm);
      final t = await q.insert();
      expect(t.id, 1);
      expect(t.name, "Fred");
    });
  });

  group("Static method insertObject(..) in `Query`", () {
    test("works given a proper object.", () async {
      context = await contextWithModels([TestModel]);
      final o = await Query.insertObject(context, TestModel()..name = "Bob");
      expect(o.id, isNotNull);
      expect(o.name, "Bob");
    });
  });

  group("Static method insertObjects(..) in `Query`", () {
    test("works given multiple objects and returns the them as a result.",
        () async {
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

      expect(bob, isA<TestModel>());
      expect(bob.id, greaterThan(0));
      expect(bob.name, "bob");
      expect(bob.emailAddress, "1@a.com");

      expect(jay, isA<TestModel>());
      expect(jay.id, greaterThan(0));
      expect(jay.name, "jay");
      expect(jay.emailAddress, "2@a.com");
    });

    test(
        "fails when at least one bad object is give and does not insert any objects into the database.",
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
        fail('should not be reached');
      } on QueryException catch (e) {
        expectNullViolation(e, columnName: "simple.name");
      }

      final insertedModels = await Query<TestModel>(context).fetch();
      expect(insertedModels, isEmpty);
    });
  });

  group("Method insertMany(..) in `Query`", () {
    test("works given an empty list.", () async {
      context = await contextWithModels([TestModel]);

      var q = Query<TestModel>(context);

      final models = await q.insertMany([]);
      expect(models, isEmpty);

      final modelsInDb = await Query<TestModel>(context).fetch();
      expect(modelsInDb, isEmpty);
    });

    test("works given a list with one element.", () async {
      context = await contextWithModels([TestModel]);

      var q = Query<TestModel>(context);

      final models = await q.insertMany([TestModel()..name = "a"]);
      expect(models, hasLength(1));
      expect(models.first.name, "a");

      final modelsInDb = await Query<TestModel>(context).fetch();
      expect(modelsInDb, hasLength(1));
      expect(modelsInDb.first.name, "a");
    });

    test("works given a list with two elements.", () async {
      context = await contextWithModels([TestModel]);

      var goodModel = TestModel()
        ..name = "alice"
        ..emailAddress = "a@a.com";

      var conflicModel = TestModel()
        ..name = "bob"
        ..emailAddress = "b@a.com";

      await Query<TestModel>(context).insertMany([goodModel, conflicModel]);

      final query = Query<TestModel>(context)
        ..sortBy((tm) => tm.id, QuerySortOrder.ascending);

      final modelsInDb = await query.fetch();

      expect(modelsInDb, hasLength(2));
      expect(modelsInDb.first.name, "alice");
      expect(modelsInDb.first.emailAddress, "a@a.com");
      expect(modelsInDb.last.name, "bob");
      expect(modelsInDb.last.emailAddress, "b@a.com");
    });

    test("works given a list with two elements with different fields filled.",
        () async {
      context = await contextWithModels([NullableObject]);

      await Query<NullableObject>(context).insertMany([
        NullableObject()..a = "a",
        NullableObject()..b = "b",
        NullableObject(),
      ]);

      final query = Query<NullableObject>(context)
        ..sortBy((tm) => tm.id, QuerySortOrder.ascending);

      final modelsInDb = await query.fetch();

      expect(modelsInDb, hasLength(3));
      expect(modelsInDb[0].a, "a");
      expect(modelsInDb[0].b, isNull);
      expect(modelsInDb[1].a, isNull);
      expect(modelsInDb[1].b, "b");
      expect(modelsInDb[2].a, isNull);
      expect(modelsInDb[2].b, isNull);
    });

    test("works given a list with one element and no values set to it.",
        () async {
      context = await contextWithModels([NullableObject]);

      await Query<NullableObject>(context).insertMany([
        NullableObject(),
      ]);

      final query = Query<NullableObject>(context)
        ..sortBy((tm) => tm.id, QuerySortOrder.ascending);

      final modelsInDb = await query.fetch();

      expect(modelsInDb, hasLength(1));
      expect(modelsInDb[0].a, isNull);
      expect(modelsInDb[0].b, isNull);
    });

    test(
        "fails when at least one bad object is give and does not insert any objects into the database.",
        () async {
      context = await contextWithModels([TestModel]);

      var goodModel = TestModel()
        ..name = "bob"
        ..emailAddress = "1@a.com";

      var badModel = TestModel()
        ..name = null
        ..emailAddress = "2@a.com";

      try {
        await Query<TestModel>(context).insertMany([goodModel, badModel]);
        fail("should not be reached");
      } on QueryException catch (e) {
        expectNullViolation(e, columnName: "simple.name");
      }

      final modelsInDb = await Query<TestModel>(context).fetch();
      expect(modelsInDb, isEmpty);
    });

    test(
        "fails when two of the records given conflict on a unique field "
        "and does not insert any objects into the database.", () async {
      context = await contextWithModels([TestModel]);

      var goodModel = TestModel()
        ..name = "alice"
        ..emailAddress = "1@a.com";

      var conflicModel = TestModel()
        ..name = "bob"
        ..emailAddress = "1@a.com";

      try {
        await Query<TestModel>(context).insertMany([goodModel, conflicModel]);
        fail("should not be reached");
      } on QueryException catch (e) {
        expectUniqueViolation(e);
      }

      final modelsInDb = await Query<TestModel>(context).fetch();
      expect(modelsInDb, isEmpty);
    });

    test(
        "can be given returning prop "
        "and does not insert any objects into the database.", () async {
      context = await contextWithModels([TestModel]);

      final query = Query<TestModel>(context)
        ..returningProperties((tm) => [tm.id]);

      final result = await query.insertMany([
        TestModel()
          ..name = "alice"
          ..emailAddress = "a@a.com"
      ]);

      expect(result, hasLength(1));
      expect(result.first.id, isNotNull);
      expect(result.first.name, isNull);
      expect(result.first.emailAddress, isNull);
    });
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

  @Relate(#posts)
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

class NullableObject extends ManagedObject<_NullableObject>
    implements _NullableObject {}

class _NullableObject {
  @primaryKey
  int id;

  @Column(nullable: true)
  String a;
  @Column(nullable: true)
  String b;
}

enum EnumValues { abcd, efgh, other18 }

final doesNotContain = (matcher) => isNot(contains(matcher));

void expectNullViolation(QueryException exception, {String columnName}) {
  expect(exception.event, QueryExceptionEvent.input);
  expect(exception.message, contains("non_null_violation"));
  expect((exception.underlyingException as PostgreSQLException).code, "23502");

  if (columnName != null) {
    expect(exception.response.body["detail"], contains("simple.name"));
  }
}

void expectUniqueViolation(QueryException exception) {
  expect(exception.event, QueryExceptionEvent.conflict);
  expect(exception.message, contains("entity_already_exists"));
  expect((exception.underlyingException as PostgreSQLException).code, "23505");
  expect(exception.response.statusCode, 409);
}
