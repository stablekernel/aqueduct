import 'dart:async';
import 'dart:io';

import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  group("Standard operations", () {
    var app = Application<TestChannel>();
    Controller.letUncaughtExceptionsEscape = true;
    app.options.port = 8888;
    List<TestModel> allObjects = [];

    var clientWithScope = (String scopes) {
      return Agent.onPort(app.options.port)..headers['Authorization'] = scopes;
    };

    var insufficientScopeMatch =
        (String scope) => {'error': 'insufficient_scope', 'scope': scope};

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

    test("Can get one object with appropriate scope", () async {
      var resp = await clientWithScope('get').request("/controller/2").get();
      expect(resp, hasResponse(200, body: allObjects[1].asMap()));
    });

    test("Can not get one object without the appropriate scope", () async {
      var resp = await clientWithScope('non').request("/controller/2").get();
      expect(resp, hasResponse(403, body: insufficientScopeMatch('get')));
    });

    test("Can get all objects with appropriate scope", () async {
      var resp = await clientWithScope('getAll').request("/controller").get();
      expect(resp,
          hasResponse(200, body: allObjects.map((m) => m.asMap()).toList()));
    });

    test("Can not get all objects without the appropriate scope", () async {
      var resp = await clientWithScope('non').request("/controller").get();
      expect(resp, hasResponse(403, body: insufficientScopeMatch('getAll')));
    });

    test("Can update an object with the appropriate scope", () async {
      var expectedMap = {
        "id": 2,
        "name": "Fred",
        "createdAt": allObjects[1].createdAt.toIso8601String()
      };

      var resp = await (clientWithScope('put').request("/controller/2")
            ..body = {"name": "Fred"})
          .put();
      expect(resp, hasResponse(200, body: expectedMap));
    });

    test("Can not update an object without the appropriate scope", () async {
      var resp = await (clientWithScope('non').request("/controller/2")
            ..body = {"name": "Fred"})
          .put();
      expect(resp, hasResponse(403, body: insufficientScopeMatch('put')));
    });

    test("Can create an object with the appropriate scope", () async {
      var resp = await (clientWithScope('post').request("/controller")
            ..body = {
              "name": "John",
              "createdAt": DateTime(2000, 12, 12).toUtc().toIso8601String()
            })
          .post();

      var expectedMap = {
        "id": allObjects.length + 1,
        "name": "John",
        "createdAt": DateTime(2000, 12, 12).toUtc().toIso8601String()
      };
      expect(resp, hasResponse(200, body: expectedMap));
    });

    test("Can not create an object without the appropriate scope", () async {
      var resp = await (clientWithScope('non').request("/controller")
            ..body = {
              "name": "John",
              "createdAt": DateTime(2000, 12, 12).toUtc().toIso8601String()
            })
          .post();
      expect(resp, hasResponse(403, body: insufficientScopeMatch('post')));
    });

    test("Can delete object with the appropriate scope", () async {
      expect(await clientWithScope('delete').request("/controller/2").delete(),
          hasStatus(200));
      expect(await clientWithScope('get').request("/controller/2").get(),
          hasStatus(404));
    });

    test("Can not delete object withput the appropriate scope", () async {
      expect(await clientWithScope('non').request("/controller/3").delete(),
          hasResponse(403, body: insufficientScopeMatch('delete')));
      expect(await clientWithScope('get').request("/controller/3").get(),
          hasStatus(200));
    });
  });
}

class AuthorizerMock extends Controller {
  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    final authHeader =
        request.raw.headers.value(HttpHeaders.authorizationHeader);
    if (authHeader != null) {
      final scopes =
          authHeader.split(' ').map((scopeStr) => AuthScope(scopeStr)).toList();
      request.authorization =
          Authorization('no_client', 0, null, scopes: scopes);
    }
    return request;
  }
}

class TestChannel extends ApplicationChannel {
  ManagedContext context;
  AuthServer authServer;

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
    router.route("/controller/[:id]").link(() => AuthorizerMock()).link(() =>
        ManagedObjectController<TestModel>(context,
            scopes: const ActionScopes(
                find: ['get'],
                index: ['getAll'],
                create: ['post'],
                update: ['put'],
                delete: ['delete'])));
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
