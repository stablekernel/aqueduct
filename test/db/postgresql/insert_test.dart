// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ModelContext context = null;

  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Insert Bad Key", () async {
    context = await contextWithModels([TestModel]);

    var insertReq = new Query<TestModel>()
      ..valueMap = {
        "name": "bob",
        "emailAddress": "bk@a.com",
        "bad_key": "doesntmatter"
      };

    var successful = false;
    try {
      await insertReq.insert();
      successful = true;
    } on QueryException catch (e) {
      expect(e.message, "Property bad_key in values does not exist on simple");
      expect(e.statusCode, 400);
      expect(e.errorCode, -1);
    }
    expect(successful, false);
  });

  test("Inserting an object that violated a unique constraint fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "dup@a.com";

    var insertReq = new Query<TestModel>()..values = m;
    await insertReq.insert();

    var insertReqDup = new Query<TestModel>()..values = m;

    var successful = false;
    try {
      await insertReqDup.insert();
      successful = true;
    } catch (e) {
      expect(e.statusCode, 409);
      expect(e.errorCode, 23505);
    }
    expect(successful, false);

    m.emailAddress = "dup1@a.com";
    var insertReqFollowup = new Query<TestModel>()..values = m;

    var result = await insertReqFollowup.insert();

    expect(result.emailAddress, "dup1@a.com");
  });

  test("Inserting an object works and returns the object", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "1@a.com";

    var insertReq = new Query<TestModel>()..values = m;

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

    var insertReq = new Query<TestModel>()..values = m;

    var result = await insertReq.insert();

    var readReq = new Query<TestModel>()
      ..predicate = new Predicate("emailAddress = @email", {"email": "2@a.com"});

    result = await readReq.fetchOne();
    expect(result.name, "bob");
  });

  test("Inserting an object without required key fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()..emailAddress = "required@a.com";

    var insertReq = new Query<TestModel>()..values = m;

    var successful = false;
    try {
      await insertReq.insert();
      successful = true;
    } catch (e) {
      expect(e.statusCode, 400);
      expect(e.errorCode, 23502);
    }
    expect(successful, false);
  });

  test("Inserting an object via a values map works and returns appropriate object", () async {
    context = await contextWithModels([TestModel]);

    var insertReq = new Query<TestModel>()
      ..valueMap = {"id": 20, "name": "Bob"}
      ..resultProperties = ["id", "name"];

    var value = await insertReq.insert();
    expect(value.id, 20);
    expect(value.name, "Bob");
    expect(value.asMap().containsKey("emailAddress"), false);

    insertReq = new Query<TestModel>()
      ..valueMap = {"id": 21, "name": "Bob"}
      ..resultProperties = ["id", "name", "emailAddress"];

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
    var q = new Query<GenUser>()
      ..values = u;
    u = await q.insert();

    var p = new GenPost()
      ..owner = u
      ..text = "1";
    var pq = new Query<GenPost>()
      ..values = p;
    p = await pq.insert();

    expect(p.id, greaterThan(0));
    expect(p.owner.id, greaterThan(0));
  });

  test("Timestamp inserted correctly by default", () async {
    context = await contextWithModels([GenTime]);

    var t = new GenTime()..text = "hey";

    var q = new Query<GenTime>()..values = t;

    var result = await q.insert();

    expect(result.dateCreated is DateTime, true);
    expect(result.dateCreated.difference(new DateTime.now()).inSeconds <= 0, true);
  });

  test("Transient values work correctly", () async {
    context = await contextWithModels([TransientModel]);

    var t = new TransientModel()..value = "foo";

    var q = new Query<TransientModel>()..values = t;
    var result = await q.insert();
    expect(result.transientValue, null);
  });

  test("JSON -> Insert with List", () async {
    context = await contextWithModels([GenUser, GenPost]);

    var json = {
      "name" : "Bob",
      "posts" : [
        {"text" : "Post"}
      ]
    };

    var u = new GenUser()
      ..readMap(json);

    var q = new Query<GenUser>()
      ..values = u;

    var result = await q.insert();
    expect(result.id, greaterThan(0));
    expect(result.name, "Bob");
    expect(result.posts, isNull);

    var pq = new Query<GenPost>();
    expect(await pq.fetch(), hasLength(0));
  });
}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;

  @ColumnAttributes(nullable: true, unique: true)
  String emailAddress;

  static String tableName() {
    return "simple";
  }
}

class GenUser extends Model<_GenUser> implements _GenUser {}
class _GenUser {
  @primaryKey
  int id;
  String name;

  OrderedSet<GenPost> posts;
}

class GenPost extends Model<_GenPost> implements _GenPost {}
class _GenPost {
  @primaryKey
  int id;
  String text;

  @RelationshipInverse(#posts)
  GenUser owner;
}

class GenTime extends Model<_GenTime> implements _GenTime {}

class _GenTime {
  @primaryKey
  int id;

  String text;

  @ColumnAttributes(defaultValue: "(now() at time zone 'utc')")
  DateTime dateCreated;
}

class TransientModel extends Model<_Transient> implements _Transient {
  @transientAttribute
  String transientValue;
}

class _Transient {
  @primaryKey
  int id;

  String value;
}
