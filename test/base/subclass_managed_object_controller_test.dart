import 'dart:async';

import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  group("Standard operations", () {
    var app = new Application<TestSink>();
    RequestController.letUncaughtExceptionsEscape = true;
    app.configuration.port = 8081;
    var client = new TestClient.onPort(app.configuration.port);
    List<TestModel> allObjects = [];

    setUpAll(() async {
      await app.test();

      var now = new DateTime.now().toUtc();
      for (var i = 0; i < 5; i++) {
        var q = new Query<TestModel>()
          ..values.createdAt = now
          ..values.name = "$i";
        allObjects.add(await q.insert());

        now = now.add(new Duration(seconds: 1));
      }
    });

    tearDownAll(() async {
      await app.mainIsolateSink.context.persistentStore.close();
      await app.stop();
    });

    test("Can get one object", () async {
      var resp = await client.request("/controller/2").get();
      expect(resp, hasResponse(200, {"data": allObjects[1].asMap()}));
    });

    test("Missing object returns overridden status code", () async {
      var resp = await client.request("/controller/1").get();
      expect(resp, hasStatus(403));
    });

    test("Can get all objects", () async {
      var resp = await client.request("/controller").get();
      var sublist = allObjects.sublist(1);
      expect(resp, hasResponse(200, {"data" : sublist.map((m) => m.asMap()).toList()}));
    });

    test("Can update an object", () async {
      var expectedMap = {
        "id": 2,
        "name": "Mr. Fred",
        "createdAt": allObjects[1].createdAt.toIso8601String()
      };

      var resp = await (client.request("/controller/2")
        ..json = {"name": "Fred"})
          .put();
      expect(resp, hasResponse(200, {"data": expectedMap}));
    });

    test("Missing object for update returns overridden status code", () async {
      var resp = await (client.request("/controller/25")
        ..json = {"name": "Fred"})
          .put();

      expect(resp, hasStatus(403));
    });

    test("Can create an object", () async {
      var resp = await (client.request("/controller")
        ..json = {
          "name": "John",
          "createdAt": new DateTime(2000, 12, 12).toUtc().toIso8601String()
        })
          .post();

      var expectedMap = {
        "id": allObjects.length + 1,
        "name": "Mr. John",
        "createdAt": new DateTime(2000, 12, 12).toUtc().toIso8601String()
      };
      expect(resp, hasResponse(200, {"data": expectedMap}));
    });

    test("Can delete object", () async {
      expect(await client.request("/controller/2").delete(), hasStatus(202));
      expect(await client.request("/controller/2").get(), hasStatus(403));
    });

    test("Delete object query can be modified", () async {
      expect(await client.request("/controller/3").delete(), hasStatus(301));
      expect(await client.request("/controller/3").get(), hasStatus(200));
    });

    test("Delete non-existent object can override response", () async {
      expect(await client.request("/controller/25").delete(), hasStatus(403));
    });
  });
}

class TestSink extends RequestSink {
  TestSink(ApplicationConfiguration opts) : super(opts) {
    var dataModel = new ManagedDataModel([TestModel]);
    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo(
        "dart", "dart", "localhost", 5432, "dart_test");
    context = new ManagedContext(dataModel, persistentStore);
    ManagedContext.defaultContext = context;
  }

  ManagedContext context;

  @override
  Future willOpen() async {
    var targetSchema = new Schema.fromDataModel(context.dataModel);
    var schemaBuilder = new SchemaBuilder.toSchema(
        context.persistentStore, targetSchema,
        isTemporary: true);

    var commands = schemaBuilder.commands;
    for (var cmd in commands) {
      await context.persistentStore.execute(cmd);
    }
  }

  @override
  void setupRouter(Router router) {
    router
        .route("/controller/[:id]")
        .generate(() => new Subclass());
  }
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @managedPrimaryKey
  int id;

  String name;
  DateTime createdAt;
}

class Subclass extends ManagedObjectController<TestModel> {
  @override
  Future<Query<TestModel>> willFindObjectWithQuery(
      Query<TestModel> query) async {
    query.where.name = whereIn(["1", "2", "3"]);
    return query;
  }

  @override
  Future<Response> didFindObject(TestModel result) async {
    return new Response.ok({"data": result.asMap()});
  }

  @override
  Future<Response> didNotFindObject() async {
    return new Response.forbidden();
  }

  @override
  Future<Query<TestModel>> willInsertObjectWithQuery(
      Query<TestModel> query) async {
    query.values.name = "Mr. " + query.values.name;
    return query;
  }

  @override
  Future<Response> didInsertObject(TestModel object) async {
    return new Response.ok({"data" : object.asMap()});
  }

  @override
  Future<Query<TestModel>> willDeleteObjectWithQuery(
      Query<TestModel> query) async {
    if (request.path.variables["id"] == "3") {
      throw new HTTPResponseException(301, "invalid");
    }
    return query;
  }

  @override
  Future<Response> didDeleteObjectWithID(dynamic id) async {
    return new Response.accepted();
  }

  @override
  Future<Response> didNotFindObjectToDeleteWithID(dynamic id) async {
    return new Response.forbidden();
  }

  @override
  Future<Query<TestModel>> willUpdateObjectWithQuery(
      Query<TestModel> query) async {
    query.values.name = "Mr. " + query.values.name;
    return query;
  }

  @override
  Future<Response> didUpdateObject(TestModel object) async {
    return new Response.ok({"data": object.asMap()});
  }

  @override
  Future<Response> didNotFindObjectToUpdateWithID(dynamic id) async {
    return new Response.forbidden();
  }

  @override
  Future<Query<TestModel>> willFindObjectsWithQuery(
      Query<TestModel> query) async {
    query.where.id = whereGreaterThan(1);
    return query;
  }

  @override
  Future<Response> didFindObjects(List<TestModel> objects) async {
    return new Response.ok({"data" : objects.map((t) => t.asMap()).toList()});
  }

}