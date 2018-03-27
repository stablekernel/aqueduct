// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';
import 'package:postgres/postgres.dart';

void main() {
  ManagedContext context;

  tearDown(() async {
    await context?.close();
    context = null;
  });

  test("Accessing valueObject of Query automatically creates an instance",
      () async {
    context = await contextWithModels([TestModel]);

    var q = new Query<TestModel>(context)..values.id = 1;

    expect(q.values.id, 1);
  });

  test("Insert Bad Key", () async {
    context = await contextWithModels([TestModel]);

    var insertReq = new Query<TestModel>(context)
      ..valueMap = {
        "name": "bob",
        "emailAddress": "bk@a.com",
        "bad_key": "doesntmatter"
      };

    try {
      await insertReq.insert();
      expect(true, false);
    } on ArgumentError catch (e) {
      expect(
          e.toString(), contains("Column 'bad_key' does not exist for table 'simple'"));
    }
  });

  test("Inserting an object that violated a unique constraint fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "dup@a.com";

    var insertReq = new Query<TestModel>(context)..values = m;
    await insertReq.insert();

    var insertReqDup = new Query<TestModel>(context)..values = m;

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
    var insertReqFollowup = new Query<TestModel>(context)..values = m;

    var result = await insertReqFollowup.insert();

    expect(result.emailAddress, "dup1@a.com");
  });

  test("Insert an object that violates a unique set constraint fails with conflict", () async {
    context = await contextWithModels([MultiUnique]);

    var q = new Query<MultiUnique>(context)
      ..values.a = "a"
      ..values.b = "b";

    await q.insert();

    q = new Query<MultiUnique>(context)
      ..values.a = "a"
      ..values.b = "a";

    await q.insert();

    q = new Query<MultiUnique>(context)
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

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "1@a.com";

    var insertReq = new Query<TestModel>(context)..values = m;

    var result = await insertReq.insert();

    expect(result is TestModel, true);
    expect(result.id, greaterThan(0));
    expect(result.name, "bob");
    expect(result.emailAddress, "1@a.com");
  });

  test("Inserting an object works", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "2@a.com";

    var insertReq = new Query<TestModel>(context)..values = m;

    var result = await insertReq.insert();

    var readReq = new Query<TestModel>(context)
      ..predicate =
          new QueryPredicate("emailAddress = @email", {"email": "2@a.com"});

    result = await readReq.fetchOne();
    expect(result.name, "bob");
  });

  test("Inserting an object without required key fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()..emailAddress = "required@a.com";

    var insertReq = new Query<TestModel>(context)..values = m;

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

    var insertReq = new Query<TestModel>(context)
      ..valueMap = {"id": 20, "name": "Bob"}
      ..returningProperties((t) => [t.id, t.name]);

    var value = await insertReq.insert();
    expect(value.id, 20);
    expect(value.name, "Bob");
    expect(value.asMap().containsKey("emailAddress"), false);

    insertReq = new Query<TestModel>(context)
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

    var u = new GenUser()..name = "Joe";
    var q = new Query<GenUser>(context)..values = u;
    u = await q.insert();

    var p = new GenPost()
      ..owner = u
      ..text = "1";
    var pq = new Query<GenPost>(context)..values = p;
    p = await pq.insert();

    expect(p.id, greaterThan(0));
    expect(p.owner.id, greaterThan(0));
  });

  test("Timestamp inserted correctly by default", () async {
    context = await contextWithModels([GenTime]);

    var t = new GenTime()..text = "hey";

    var q = new Query<GenTime>(context)..values = t;

    var result = await q.insert();

    expect(result.dateCreated is DateTime, true);
    expect(
        result.dateCreated.difference(new DateTime.now()).inSeconds <= 0, true);
  });

  test("Can insert timestamp manually", () async {
    context = await contextWithModels([GenTime]);

    var dt = new DateTime.now();
    var t = new GenTime()
      ..dateCreated = dt
      ..text = "hey";

    var q = new Query<GenTime>(context)..values = t;

    var result = await q.insert();

    expect(result.dateCreated is DateTime, true);
    expect(
        result.dateCreated.difference(dt).inSeconds == 0, true);
  });

  test("Transient values work correctly", () async {
    context = await contextWithModels([TransientModel]);

    var t = new TransientModel()..value = "foo";

    var q = new Query<TransientModel>(context)..values = t;
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

    var u = new GenUser()..readFromMap(json);

    var q = new Query<GenUser>(context)..values = u;

    var result = await q.insert();
    expect(result.id, greaterThan(0));
    expect(result.name, "Bob");
    expect(result.posts, isNull);

    var pq = new Query<GenPost>(context);
    expect(await pq.fetch(), hasLength(0));
  });

  test("Insert object with no keys", () async {
    context = await contextWithModels([BoringObject]);

    var q = new Query<BoringObject>(context);
    var result = await q.insert();
    expect(result.id, greaterThan(0));
  });

  test("Can use insert private properties", () async {
    context = await contextWithModels([PrivateField]);

    await (new Query<PrivateField>(context)..values.public = "abc").insert();
    var q = new Query<PrivateField>(context);
    var result = await q.fetch();
    expect(result.first.public, "abc");
  });

  test("Can use enum to set property to be stored in db", () async {
    context = await contextWithModels([EnumObject]);

    var q = new Query<EnumObject>(context)
      ..values.enumValues = EnumValues.efgh;

    var result = await q.insert();
    expect(result.enumValues, EnumValues.efgh);
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

class BoringObject extends ManagedObject<_BoringObject> implements _BoringObject {}
class _BoringObject {
  @primaryKey
  int id;
}

class PrivateField extends ManagedObject<_PrivateField> implements _PrivateField {
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

  EnumValues enumValues;
}

class MultiUnique extends ManagedObject<_MultiUnique> implements _MultiUnique {}
@Table.unique(const [#a, #b])
class _MultiUnique {
  @primaryKey
  int id;

  String a;
  String b;
}

enum EnumValues {
  abcd, efgh, other18
}