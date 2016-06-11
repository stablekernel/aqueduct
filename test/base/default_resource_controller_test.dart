import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() {
  group("Standard operations", () {
    Application app = null;
    List<TestModel> allObjects = [];

    setUpAll(() async {
      app = new Application<TestPipeline>();
      app.configuration.port = 8080;
      await app.start(runOnMainIsolate: true);

      var now = new DateTime.now().toUtc();
      for (var i = 0; i < 5; i++) {
        var q = new ModelQuery<TestModel>()
            ..values.createdAt = now
            ..values.name = "$i";
        allObjects.add(await q.insert());

        now = now.add(new Duration(seconds: 1));
      }
    });

    tearDownAll(() async {
      await app.stop();
    });

    test("Can get one object", () async {
      var resp = await http.get("http://localhost:8080/controller/1");
      expect(resp.statusCode, 200);
      expect(JSON.decode(resp.body), allObjects.first.asMap());
    });

    test("Can get all objects", () async {
      var resp = await http.get("http://localhost:8080/controller");
      expect(resp.statusCode, 200);
      expect(JSON.decode(resp.body), allObjects.map((m) => m.asMap()).toList());
    });

    test("Can update an object", () async {
      var expectedMap = {
        "id" : 1,
        "name" : "Fred",
        "createdAt" : allObjects.first.createdAt.toIso8601String()
      };

      var resp = await http.put("http://localhost:8080/controller/1", headers: {
        "Content-Type" : "application/json"
      }, body: JSON.encode({
        "name" : "Fred"
      }));
      expect(resp, hasResponse(200, [], matchesJSON(expectedMap)));

      expect(await http.get("http://localhost:8080/controller/1"), hasResponse(200, [], matchesJSON(expectedMap)));
      expect(await http.get("http://localhost:8080/controller/2"), hasResponse(200, [], matchesJSON(allObjects[1].asMap())));
    });

    test("Can create an object", () async {
      var resp = await http.post("http://localhost:8080/controller", headers: {
        "Content-Type" : "application/json"
      }, body: JSON.encode({
        "name" : "John",
        "createdAt" : new DateTime(2000, 12, 12).toIso8601String()
      }));

      var expectedMap = {
        "id" : allObjects.length + 1,
        "name" : "John",
        "createdAt" : "2000-12-12T00:00:00.000Z"
      };
      expect(resp, hasResponse(200, [], matchesJSON(expectedMap)));
      expect(await http.get("http://localhost:8080/controller/${expectedMap["id"]}"), hasResponse(200, [], matchesJSON(expectedMap)));
    });

    test("Can delete object", () async {
      expect(await http.delete("http://localhost:8080/controller/1"), hasStatus(200));
      expect(await http.get("http://localhost:8080/controller/1"), hasStatus(404));
    });
  });

  group("Standard operation failure cases", () {
    Application app = null;

    setUpAll(() async {
      app = new Application<TestPipeline>();
      app.configuration.port = 8080;
      await app.start(runOnMainIsolate: true);
    });

    tearDownAll(() async {
      await app.stop();
    });

    test("Get an object with the wrong type of path param returns 404", () async {
      var resp = await http.get("http://localhost:8080/controller/one");
      expect(resp.statusCode, 404);
    });

    test("Put an object with the wrong type of path param returns 404", () async {
      var resp = await http.put("http://localhost:8080/controller/one", headers: {
        "Content-Type" : "application/json"
      }, body: JSON.encode({
        "name" : "Fred"
      }));
      expect(resp.statusCode, 404);
    });

    test("Delete an object with the wrong type of path param returns 404", () async {
      var resp = await http.delete("http://localhost:8080/controller/one");
      expect(resp.statusCode, 404);
    });
  });

  group("Objects that don't exist", () {
    Application app = null;

    setUpAll(() async {
      app = new Application<TestPipeline>();
      app.configuration.port = 8080;
      await app.start(runOnMainIsolate: true);
    });

    tearDownAll(() async {
      await app.stop();
    });

    test("Can't get object that doesn't exist - 404", () async {
      var resp = await http.get("http://localhost:8080/controller/1");
      expect(resp.statusCode, 404);

    });

    test("Can get all objects - there are none", () async {
      var resp = await http.get("http://localhost:8080/controller");
      expect(resp.statusCode, 200);
      expect(JSON.decode(resp.body), []);
    });

    test("Updating an object returns 404", () async {
      var resp = await http.put("http://localhost:8080/controller/1", headers: {
        "Content-Type" : "application/json"
      }, body: JSON.encode({
        "name" : "Fred"
      }));
      expect(resp, hasStatus(404));
    });

    test("Delete nonexistant object is 404", () async {
      expect(await http.delete("http://localhost:8080/controller/1"), hasStatus(404));
    });
  });

  group("Extended GET requests", () {
    Application app = null;
    List<TestModel> allObjects = [];

    setUpAll(() async {

      app = new Application<TestPipeline>();
      app.configuration.port = 8080;
      await app.start(runOnMainIsolate: true);

      var now = new DateTime.now().toUtc();
      for (var i = 0; i < 10; i++) {
        var q = new ModelQuery<TestModel>()
          ..values.createdAt = now
          ..values.name = "${9 - i}";
        allObjects.add(await q.insert());

        now = now.add(new Duration(seconds: 1));
      }
    });

    tearDownAll(() async {
      await app.stop();
    });

    test("Can get all objects w/ count and offset", () async {
      var resp = await http.get("http://localhost:8080/controller?count=2&offset=1");
      expect(resp, hasResponse(200, [], matchesJSONExactly(allObjects.sublist(1, 2).map((m) => m.asMap()).toList())));
    });

    test("Can get all objects w/ sort descriptor", () async {
      var resp = await http.get("http://localhost:8080/controller?sortBy=name,asc");
      expect(resp, hasResponse(200, [], matchesJSONExactly(allObjects.reversed.map((m) => m.asMap()).toList())));

      resp = await http.get("http://localhost:8080/controller?sortBy=createdAt,asc");
      expect(resp, hasResponse(200, [], matchesJSONExactly(allObjects.map((m) => m.asMap()).toList())));
    });

    test("Getting all objects with sort descriptor referencing unknown key fails", () async {
      var resp = await http.get("http://localhost:8080/controller?sortBy=foobar,asc");
      expect(resp, hasResponse(400, [], matchesJSON({"error" : "sortBy key foobar does not exist for _TestModel"})));
    });

    test("Getting all objects with a unknown sort descriptor order fails", () async {
      var resp = await http.get("http://localhost:8080/controller?sortBy=name,name");
      expect(resp, hasResponse(400, [], matchesJSON({"error" : "sortBy order must be either asc or desc, not name"})));
    });

    test("Paging after", () async {
      var resp = await http.get("http://localhost:8080/controller?pageBy=createdAt&pageAfter=${allObjects[5].createdAt.toIso8601String()}");
      expect(resp, hasResponse(200, [], matchesJSONExactly(allObjects.sublist(6, 9).map((m) => m.asMap()).toList())));
    });

    test("Paging before", () async {
      var resp = await http.get("http://localhost:8080/controller?pageBy=createdAt&pagePrior=${allObjects[5].createdAt.toIso8601String()}");
      expect(resp, hasResponse(200, [], matchesJSONExactly(allObjects.sublist(0, 5).reversed.map((m) => m.asMap()).toList())));
    });

    test("Paging with null value", () async {
      var resp = await http.get("http://localhost:8080/controller?pageBy=createdAt&pageAfter=null");
      expect(resp, hasResponse(200, [], matchesJSONExactly(allObjects.map((m) => m.asMap()).toList())));
    });

    test("Paging with no pageAfter/pagePrior", () async {
      var resp = await http.get("http://localhost:8080/controller?pageBy=createdAt");
      expect(resp, hasResponse(400, [], matchesJSONExactly({"error" : "If defining pageBy, either pageAfter or pagePrior must be defined. 'null' is a valid value"})));
    });

    test("Paging with wrong key", () async {
      var resp = await http.get("http://localhost:8080/controller?pageBy=foobar&pagePrior=10");
      expect(resp, hasResponse(400, [], matchesJSONExactly({"error" : "pageBy key foobar does not exist for _TestModel"})));
    });
  });
}

class TestPipeline extends ApplicationPipeline {
  TestPipeline(dynamic opts) : super (opts) {
    var dataModel = new DataModel([TestModel]);
    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
    context = new ModelContext(dataModel, persistentStore);
    ModelContext.defaultContext = context;
  }

  ModelContext context = null;

  @override
  Future willOpen() async {
    var generator = new SchemaGenerator(context.persistentStore, context.dataModel);
    var specificGenerator = new PostgreSQLSchemaGenerator(generator.serialized, temporary: true);
    for (var cmd in specificGenerator.commands) {
      await context.persistentStore.execute(cmd);
    }
  }

  @override
  void addRoutes() {
    router
        .route("/controller/[:id]")
        .then(() => new ResourceController<TestModel>());
  }
}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;
  DateTime createdAt;
}
