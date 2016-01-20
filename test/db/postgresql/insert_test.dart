// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'package:postgresql/postgresql.dart' as postgresql;

void main() {
  PostgresModelAdapter adapter;

  setUp(() async {
    adapter = new PostgresModelAdapter(null, () async {
      var uri = 'postgres://dart:dart@localhost:5432/dart_test';
      return await postgresql.connect(uri, timeZone: 'UTC');
    });
  });

  tearDown(() {
    adapter.close();
    adapter = null;
  });

  test("Insert Bad Key", () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    var insertReq = new Query<TestModel>()
      ..values = {
        "name": "bob",
        "emailAddress": "bk@a.com",
        "bad_key": "doesntmatter"
      };

    try {
      await insertReq.insert(adapter);
      fail("Succeeded with inserting bad key");
    } catch (e) {
      expect(e.statusCode, 400);
      expect(e.errorCode, 42703);
    }
  });

  test("Inserting an object that violated a unique constraint fails", () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "dup@a.com";

    var insertReq = new Query<TestModel>()..valueObject = m;

    await insertReq.insert(adapter);

    var insertReqDup = new Query<TestModel>()..valueObject = m;

    try {
      await insertReqDup.insert(adapter);
      fail("Query should have failed to insert unique constraint object");
    } catch (e) {
      expect(e.statusCode, 409);
      expect(e.errorCode, 23505);
    }

    m.emailAddress = "dup1@a.com";
    var insertReqFollowup = new Query<TestModel>()..valueObject = m;

    var result = await insertReqFollowup.insert(adapter);

    expect(result.emailAddress, "dup1@a.com");
  });

  test("Inserting an object works and returns the object", () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "1@a.com";

    var insertReq = new Query<TestModel>()..valueObject = m;

    var result = await insertReq.insert(adapter);

    expect(result is TestModel, true);
    expect(result.id, greaterThan(0));
    expect(result.name, "bob");
    expect(result.emailAddress, "1@a.com");
  });

  test("Inserting an object works", () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "2@a.com";

    var insertReq = new Query<TestModel>()..valueObject = m;

    var result = await insertReq.insert(adapter);

    var readReq = new Query<TestModel>()
      ..predicate =
          new Predicate("emailAddress = @email", {"email": "2@a.com"});

    result = await readReq.fetchOne(adapter);
    expect(result.name, "bob");
  });

  test("Inserting an object without required key fails", () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    var m = new TestModel()..emailAddress = "required@a.com";

    var insertReq = new Query<TestModel>()..valueObject = m;

    try {
      await insertReq.insert(adapter);
      fail("Query should have failed");
    } catch (e) {
      expect(e.statusCode, 400);
      expect(e.errorCode, 23502);
    }
  });

  test(
      "Inserting an object via a values map works and returns appropriate object",
      () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    var insertReq = new Query<TestModel>()
      ..values = {"id": 20, "name": "Bob"}
      ..resultKeys = ["id", "name"];

    var value = await insertReq.insert(adapter);
    expect(value.id, 20);
    expect(value.name, "Bob");
    expect(value.asMap().containsKey("emailAddress"), false);

    insertReq = new Query<TestModel>()
      ..values = {"id": 21, "name": "Bob"}
      ..resultKeys = ["id", "name", "emailAddress"];

    value = await insertReq.insert(adapter);
    expect(value.id, 21);
    expect(value.name, "Bob");
    expect(value.emailAddress, null);
    expect(value.asMap().containsKey("emailAddress"), true);
    expect(value.asMap()["emailAddress"], null);
  });

  test("Inserting object with relationship returns embedded object", () async {
    await generateTemporarySchemaFromModels(adapter, [GenUser, GenPost]);

    var u = new GenUser()..name = "Joe";
    var q = new Query<GenUser>()..valueObject = u;
    u = await q.insert(adapter);

    var p = new GenPost()
      ..owner = u
      ..text = "1";
    q = new Query<GenPost>()..valueObject = p;
    p = await q.insert(adapter);

    expect(p.id, greaterThan(0));
    expect(p.owner.id, greaterThan(0));
  });

  test("Timestamp inserted correctly by default", () async {
    await generateTemporarySchemaFromModels(adapter, [GenTime]);

    var t = new GenTime()..text = "hey";

    var q = new Query<GenTime>()..valueObject = t;

    var result = await q.insert(adapter);

    expect(result.dateCreated is DateTime, true);
    expect(
        result.dateCreated.difference(new DateTime.now()).inSeconds <= 0, true);
  });

  test("Transient values work correctly", () async {
    await generateTemporarySchemaFromModels(adapter, [TransientModel]);

    var t = new TransientModel()..value = "foo";

    var q = new Query<TransientModel>()..valueObject = t;
    var result = await q.insert(adapter);
    expect(result.transientValue, null);
  });

  test("JSON -> Insert with List", () async {
    await generateTemporarySchemaFromModels(adapter, [GenUser, GenPost]);

    var json = {
      "name" : "Bob",
      "posts" : [
        {"text" : "Post"}
      ]
    };

    var u = new GenUser()
      ..readMap(json);

    var q = new Query<GenUser>()
      ..valueObject = u;

    var result = await q.insert(adapter);
    expect(result.id, greaterThan(0));
    expect(result.name, "Bob");
    expect(result.posts, isNull);

    q = new Query<GenPost>();
    expect(await q.fetch(adapter), hasLength(0));
  });
}

@proxy
class TestModel extends Model<TestModelBacking> implements TestModelBacking {
}

class TestModelBacking {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  @Attributes(nullable: true, unique: true)
  String emailAddress;

  static String tableName() {
    return "simple";
  }
}

@proxy
class GenUser extends Model<GenUserBacking> implements GenUserBacking {
}

class GenUserBacking {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  @RelationshipAttribute(RelationshipType.hasMany, "owner")
  List<GenPost> posts;

  static String tableName() {
    return "GenUser";
  }
}

@proxy
class GenPost extends Model<GenPostBacking> implements GenPostBacking {
}

class GenPostBacking {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String text;

  @Attributes(indexed: true, nullable: true)
  @RelationshipAttribute(RelationshipType.belongsTo, "posts")
  GenUser owner;
}

@proxy
class GenTime extends Model<GenTimeBacking> implements GenTimeBacking {
}

class GenTimeBacking {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String text;

  @Attributes(defaultValue: "(now() at time zone 'utc')")
  DateTime dateCreated;
}

@proxy
class TransientModel extends Model<TransientBacking> implements TransientBacking {
  @mappable
  String transientValue;

  noSuchMethod(i) => super.noSuchMethod(i);
}

class TransientBacking {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String value;
}
