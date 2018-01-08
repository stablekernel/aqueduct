import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:mirrors';
import '../helpers.dart';

void main() {
  HttpServer server;

  setUpAll(() {
    new ManagedContext(
        new ManagedDataModel([TestModel]), new DefaultPersistentStore());
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  group("Happy path", () {
    test("Can read Map body object into HTTPSerializable",  () async {
      server = await enableController("/", TestController);
      var m = {
        "id": 2,
        "name": "Bob"
      };
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(JSON.decode(response.body), m);
    });

    test("Can read List<Map> body object into List<HTTPSerializable>", () async {
      server = await enableController("/", ListTestController);
      var m = [
        {
          "id": 2,
          "name": "Bob"
        },
        {
          "id": 3,
          "name": "Fred"
        }
      ];
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(JSON.decode(response.body), m);
    });

    test("Can read empty List body", () async {
      server = await enableController("/", ListTestController);
      var m = [];
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(JSON.decode(response.body), m);
    });

    test("Body arg can be optional", () async {
      server = await enableController("/", OptionalTestController);
      var m = {
        "id": 2,
        "name": "Bob"
      };
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(JSON.decode(response.body), m);

      response = await http.post("http://localhost:4040/");
      expect(response.statusCode, 200);
      expect(response.headers["content-type"], isNull);
      expect(response.body, "");
    });

    test("Can read body object declared as property", () async {
      server = await enableController("/", PropertyTestController);
      var m = {
        "id": 2,
        "name": "Bob"
      };
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(JSON.decode(response.body), m);
    });
  });

  group("Programmer error cases", () {
    test("Argument does not implement HTTPSerializable returns 500", () async {
      server = await enableController("/", NotSerializableController);
      var response = await postJSON({"k":"v"});
      expect(response.statusCode, 500);
    });

    test("List parameterized type does not implement HTTPSerializable returns 500", () async {
      server = await enableController("/", ListNotSerializableController);
      var response = await postJSON([{"k":"v"}]);
      expect(response.statusCode, 500);
    });

    test("fromMap throws uncaught error should return a 500", () async {
      server = await enableController("/", CrashController);
      var m = {
        "id": 1,
        "name": "Crash"
      };
      var response = await postJSON(m);
      expect(response.statusCode, 500);
    });
  });

  group("Input error cases", () {
    test("Provide unknown key returns 400", () async {
      server = await enableController("/", TestController);
      var m = {
        "id": 2,
        "name": "Bob",
        "job": "programmer"
      };
      var response = await postJSON(m);
      expect(response.statusCode, 400);
      expect(JSON.decode(response.body)["error"], contains("job"));
    });

    test("Body is empty returns 400", () async {
      server = await enableController("/", TestController);
      var m = {
        "id": 2,
        "name": "Bob",
        "job": "programmer"
      };
      var response = await postJSON(m);
      expect(response.statusCode, 400);
      expect(JSON.decode(response.body)["error"], contains("job"));
    });

    test("Is List when expecting Map returns 400", () async {
      server = await enableController("/", TestController);
      var m = [{
        "id": 2,
        "name": "Bob"
      }];
      var response = await postJSON(m);
      expect(response.statusCode, 400);
      expect(JSON.decode(response.body)["error"], contains("Expected Map"));
      expect(JSON.decode(response.body)["error"], contains("got List"));
    });

    test("Is Map when expecting List returns 400", () async {
      server = await enableController("/", ListTestController);
      var m = {
        "id": 2,
        "name": "Bob"
      };
      var response = await postJSON(m);
      expect(response.statusCode, 400);
      expect(JSON.decode(response.body)["error"], contains("Expected List"));
      expect(JSON.decode(response.body)["error"], contains("got _InternalLinkedHashMap"));
    });

    test("If required body and no body included, return 400", () async {
      server = await enableController("/", TestController);
      var response = await postJSON(null);
      expect(response.statusCode, 400);
      expect(JSON.decode(response.body)["error"], contains("Missing Body"));
    });

    test("Expect list of objects, got list of strings", () async {
      server = await enableController("/", ListTestController);
      var response = await postJSON(["a", "b"]);
      expect(response.statusCode, 400);
      expect(JSON.decode(response.body)["error"], contains("Expected List<Map>"));
      expect(JSON.decode(response.body)["error"], contains("got List<String>"));
    });
  });
}

Future<http.Response> postJSON(dynamic json) {
  if (json == null) {
    return http
        .post("http://localhost:4040",
        headers: {"Content-Type": "application/json"})
        .catchError((err) => null);
  }
  return http
      .post("http://localhost:4040",
      headers: {"Content-Type": "application/json"},
      body: JSON.encode(json))
      .catchError((err) => null);
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;
}

class CrashModel implements HTTPSerializable {
  @override
  void readFromMap(dynamic requestBody) {
    throw new Exception("whatever");
  }

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

class TestController extends RESTController {
  @Operation.post()
  Future<Response> create(@Bind.body() TestModel tm) async {
    return new Response.ok(tm);
  }
}

class ListTestController extends RESTController {
  @Operation.post()
  Future<Response> create(@Bind.body() List<TestModel> tms) async {
    return new Response.ok(tms);
  }
}

class OptionalTestController extends RESTController {
  @Operation.post()
  Future<Response> create({@Bind.body() TestModel tm}) async {
    return new Response.ok(tm);
  }
}

class PropertyTestController extends RESTController {
  @Bind.body()
  TestModel tm;

  @Operation.post()
  Future<Response> create() async {
    return new Response.ok(tm);
  }
}

class NotSerializableController extends RESTController {
  @Operation.post()
  Future<Response> create(@Bind.body() Uri uri) async {
    return new Response.ok(null);
  }
}

class ListNotSerializableController extends RESTController {
  @Operation.post()
  Future<Response> create(@Bind.body() List<Uri> uri) async {
    return new Response.ok(null);
  }
}

class CrashController extends RESTController {
  @Operation.post()
  Future<Response> create(@Bind.body() CrashModel tm) async {
    return new Response.ok(null);
  }
}

Future<HttpServer> enableController(String pattern, Type controller) async {
  var router = new Router();
  router.route(pattern).link(
          () => reflectClass(controller).newInstance(new Symbol(""), []).reflectee);
  router.prepare();

  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4040);
  server.map((httpReq) => new Request(httpReq)).listen(router.receive);

  return server;
}