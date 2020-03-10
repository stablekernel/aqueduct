import 'dart:async';

import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  group("Standard operations", () {
    var app = Application<TestChannel>();
    app.options.port = 8888;
    var client = Agent.onPort(app.options.port);
    List<TestModel> allObjects = [];

    setUpAll(() async {
      await app.startOnCurrentIsolate();

      var now = DateTime.now().toUtc();
      for (var i = 0; i < 5; i++) {
        var q = Query<TestModel>(app.channel.context)
          ..values.createdAt = now
          ..values.name = "$i";
        allObjects.add(await q.insert());

        now = now.add(const Duration(seconds: 1));
      }
    });

    tearDownAll(() async {
      await app.channel.context.close();
      await app.stop();
    });

    test("Can get one object", () async {
      var resp = await client.request("/controller/2").get();
      expect(resp, hasResponse(200, body: {"data": allObjects[1].asMap()}));
    });

    test("Missing object returns overridden status code", () async {
      var resp = await client.request("/controller/1").get();
      expect(resp, hasStatus(403));
    });

    test("Can get all objects", () async {
      var resp = await client.request("/controller").get();
      var sublist = allObjects.sublist(1);
      expect(
          resp,
          hasResponse(200,
              body: {"data": sublist.map((m) => m.asMap()).toList()}));
    });

    test("Can update an object", () async {
      var expectedMap = {
        "id": 2,
        "name": "Mr. Fred",
        "createdAt": allObjects[1].createdAt.toIso8601String()
      };

      var resp = await (client.request("/controller/2")
            ..body = {"name": "Fred"})
          .put();
      expect(resp, hasResponse(200, body: {"data": expectedMap}));
    });

    test("Missing object for update returns overridden status code", () async {
      var resp = await (client.request("/controller/25")
            ..body = {"name": "Fred"})
          .put();

      expect(resp, hasStatus(403));
    });

    test("Can create an object", () async {
      var resp = await (client.request("/controller")
            ..body = {
              "name": "John",
              "createdAt": DateTime(2000, 12, 12).toUtc().toIso8601String()
            })
          .post();

      var expectedMap = {
        "id": allObjects.length + 1,
        "name": "Mr. John",
        "createdAt": DateTime(2000, 12, 12).toUtc().toIso8601String()
      };
      expect(resp, hasResponse(200, body: {"data": expectedMap}));
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

class TestChannel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    var dataModel = ManagedDataModel([TestModel]);
    var persistentStore = PostgreSQLPersistentStore(
        "dart", "dart", "localhost", 5432, "dart_test");
    context = ManagedContext(dataModel, persistentStore);

    var targetSchema = Schema.fromDataModel(context.dataModel);
    var schemaBuilder = SchemaBuilder.toSchema(
        context.persistentStore, targetSchema,
        isTemporary: true);

    var commands = schemaBuilder.commands;
    for (var cmd in commands) {
      await context.persistentStore.execute(cmd);
    }
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/controller/[:id]").link(() => Subclass(context));
    return router;
  }
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int id;

  String name;
  DateTime createdAt;
}

class Subclass extends ManagedObjectController<TestModel> {
  Subclass(ManagedContext context) : super(context);

  @override
  Future<Query<TestModel>> willFindObjectWithQuery(
      Query<TestModel> query) async {
    query.where((o) => o.name).oneOf(["1", "2", "3"]);
    return query;
  }

  @override
  Future<Response> didFindObject(TestModel result) async {
    return Response.ok({"data": result.asMap()});
  }

  @override
  Future<Response> didNotFindObject() async {
    return Response.forbidden();
  }

  @override
  Future<Query<TestModel>> willInsertObjectWithQuery(
      Query<TestModel> query) async {
    query.values.name = "Mr. ${query.values.name}";
    return query;
  }

  @override
  Future<Response> didInsertObject(TestModel object) async {
    return Response.ok({"data": object.asMap()});
  }

  @override
  Future<Query<TestModel>> willDeleteObjectWithQuery(
      Query<TestModel> query) async {
    if (request.path.variables["id"] == "3") {
      throw Response(301, null, {"error": "invalid"});
    }
    return query;
  }

  @override
  Future<Response> didDeleteObjectWithID(dynamic id) async {
    return Response.accepted();
  }

  @override
  Future<Response> didNotFindObjectToDeleteWithID(dynamic id) async {
    return Response.forbidden();
  }

  @override
  Future<Query<TestModel>> willUpdateObjectWithQuery(
      Query<TestModel> query) async {
    query.values.name = "Mr. ${query.values.name}";
    return query;
  }

  @override
  Future<Response> didUpdateObject(TestModel object) async {
    return Response.ok({"data": object.asMap()});
  }

  @override
  Future<Response> didNotFindObjectToUpdateWithID(dynamic id) async {
    return Response.forbidden();
  }

  @override
  Future<Query<TestModel>> willFindObjectsWithQuery(
      Query<TestModel> query) async {
    query.where((o) => o.id).greaterThan(1);
    return query;
  }

  @override
  Future<Response> didFindObjects(List<TestModel> objects) async {
    return Response.ok({"data": objects.map((t) => t.asMap()).toList()});
  }
}
