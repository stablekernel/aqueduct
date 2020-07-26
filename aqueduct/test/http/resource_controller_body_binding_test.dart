import 'dart:async';
import 'dart:convert';
import "dart:core";
import "dart:io";

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import "package:test/test.dart";

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  HttpServer server;

  setUpAll(() {
    ManagedContext(ManagedDataModel([TestModel]), DefaultPersistentStore());
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  group("Happy path", () {
    test("Can read Map body object into Serializable", () async {
      server = await enableController("/", () => TestController());
      var m = {"name": "Bob"};
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(json.decode(response.body), m);
    });

    test("Can read List<Map> body object into List<Serializable>", () async {
      server = await enableController("/", () => ListTestController());
      var m = [
        {"name": "Bob"},
        {"name": "Fred"}
      ];
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(json.decode(response.body), m);
    });

    test("Can read empty List body", () async {
      server = await enableController("/", () => ListTestController());
      var m = [];
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(json.decode(response.body), m);
    });

    test("Body arg can be optional", () async {
      server = await enableController("/", () => OptionalTestController());
      var m = {"name": "Bob"};
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(json.decode(response.body), m);

      response = await http.post("http://localhost:4040/");
      expect(response.statusCode, 200);
      expect(response.headers["content-type"], isNull);
      expect(response.body, "");
    });

    test("Can read body object declared as property", () async {
      server = await enableController("/", () => PropertyTestController());
      var m = {"name": "Bob"};
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(json.decode(response.body), m);
    });

    test("Can use ignore filters", () async {
      server = await enableController("/", () => FilterController());
      expect(json.decode((await postJSON({"required": "", "ignore": ""})).body),
          {"required": ""});
    });

    test("Can use error filters", () async {
      server = await enableController("/", () => FilterController());
      expect((await postJSON({"required": "", "error": ""})).statusCode, 400);
    });

    test("Can use required filters", () async {
      server = await enableController("/", () => FilterController());
      expect((await postJSON({"key": ""})).statusCode, 400);
    });

    test("Can use accept filters", () async {
      server = await enableController("/", () => FilterController());
      final response =
          await postJSON({"required": "", "accept": "", "noAccept": ""});

      expect(json.decode(response.body), {"required": "", "accept": ""});
    });

    test("Can use ignore filters on List<Serializable>", () async {
      server = await enableController("/", () => FilterListController());
      final response = await postJSON([
        {"required": ""},
        {"required": "", "ignore": ""}
      ]);

      expect(json.decode(response.body), [
        {"required": ""},
        {"required": ""}
      ]);
    });

    test("Can use error filters on List<Serializable>", () async {
      server = await enableController("/", () => FilterListController());
      expect(
          (await postJSON([
            {"required": ""},
            {"required": "", "error": ""}
          ]))
              .statusCode,
          400);
    });

    test("Can use required filters on List<Serializable>", () async {
      server = await enableController("/", () => FilterListController());
      expect(
          (await postJSON([
            {"required": ""},
            {"key": ""}
          ]))
              .statusCode,
          400);
    });

    test("Can use accept filters on List<Serializable>", () async {
      server = await enableController("/", () => FilterListController());
      final response = await postJSON([
        {"required": "", "accept": ""},
        {"required": "", "noAccept": ""}
      ]);

      expect(json.decode(response.body), [
        {"required": "", "accept": ""},
        {"required": ""}
      ]);
    });

    test("Can bind primitive map", () async {
      server = await enableController("/", () => MapController());
      var m = {"name": "Bob"};
      var response = await postJSON(m);
      expect(response.statusCode, 200);
      expect(json.decode(response.body), m);
    });

    test("Can get a list of bytes from an octet-stream", () async {
      server = await enableController("/", () => ByteListController());

      final response = await http.post("http://localhost:4040",
          headers: {"Content-Type": "application/octet-stream"},
          body: [1, 2, 3]).catchError((err) => null);

      expect(response.statusCode, 200);
      expect(response.bodyBytes, [1, 2, 3]);
    });
  });

  group("Programmer error cases", () {
    test("fromMap throws uncaught error should return a 500", () async {
      server = await enableController("/", () => CrashController());
      var m = {"id": 1, "name": "Crash"};
      var response = await postJSON(m);
      expect(response.statusCode, 500);
    });
  });

  group("Input error cases", () {
    test("Provide unknown key returns 400", () async {
      server = await enableController("/", () => TestController());
      var m = {"name": "Bob", "job": "programmer"};
      var response = await postJSON(m);
      expect(response.statusCode, 400);
      expect(json.decode(response.body)["error"], "entity validation failed");
      expect(json.decode(response.body)["reasons"].join(","), contains("job"));
    });

    test("Body is empty returns 400", () async {
      server = await enableController("/", () => TestController());
      var m = {"name": "Bob", "job": "programmer"};
      var response = await postJSON(m);
      expect(response.statusCode, 400);
      expect(json.decode(response.body)["error"], "entity validation failed");
      expect(json.decode(response.body)["reasons"].join(","), contains("job"));
    });

    test("Is List when expecting Map returns 400", () async {
      server = await enableController("/", () => TestController());
      var m = [
        {"id": 2, "name": "Bob"}
      ];
      var response = await postJSON(m);
      expect(response.statusCode, 400);
      expect(json.decode(response.body)["error"],
          contains("request entity was unexpected type"));
    });

    test("Is Map when expecting List returns 400", () async {
      server = await enableController("/", () => ListTestController());
      var m = {"id": 2, "name": "Bob"};
      var response = await postJSON(m);
      expect(response.statusCode, 400);
      expect(json.decode(response.body)["error"],
          contains("request entity was unexpected type"));
    });

    test("If required body and no body included, return 400", () async {
      server = await enableController("/", () => TestController());
      var response = await postJSON(null);
      expect(response.statusCode, 400);
      expect(json.decode(response.body)["error"],
          contains("missing required body"));
    });

    test("Expect list of objects, got list of strings", () async {
      server = await enableController("/", () => ListTestController());
      var response = await postJSON(["a", "b"]);
      expect(response.statusCode, 400);
      expect(json.decode(response.body)["error"],
          contains("request entity was unexpected type"));
    });
  });
}

Future<http.Response> postJSON(dynamic body) {
  if (body == null) {
    return http.post("http://localhost:4040", headers: {
      "Content-Type": "application/json"
    }).catchError((err) => null);
  }
  return http
      .post("http://localhost:4040",
          headers: {"Content-Type": "application/json"},
          body: json.encode(body))
      .catchError((err) => null);
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int id;

  String name;
}

class TestSerializable extends Serializable {
  Map<String, dynamic> contents;

  @override
  void readFromMap(Map<String, dynamic> object) {
    contents = object;
  }

  @override
  Map<String, dynamic> asMap() {
    return contents;
  }
}

class CrashModel extends Serializable {
  @override
  void readFromMap(dynamic requestBody) {
    throw Exception("whatever");
  }

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

class TestController extends ResourceController {
  @Operation.post()
  Future<Response> create(@Bind.body() TestModel tm) async {
    return Response.ok(tm);
  }
}

class ListTestController extends ResourceController {
  @Operation.post()
  Future<Response> create(@Bind.body() List<TestModel> tms) async {
    return Response.ok(tms);
  }
}

class OptionalTestController extends ResourceController {
  @Operation.post()
  Future<Response> create({@Bind.body() TestModel tm}) async {
    return Response.ok(tm);
  }
}

class PropertyTestController extends ResourceController {
  @Bind.body()
  TestModel tm;

  @Operation.post()
  Future<Response> create() async {
    return Response.ok(tm);
  }
}

class CrashController extends ResourceController {
  @Operation.post()
  Future<Response> create(@Bind.body() CrashModel tm) async {
    return Response.ok(null);
  }
}

class FilterController extends ResourceController {
  @Operation.post()
  Future<Response> create(
      @Bind.body(accept: [
    "accept",
    "ignore",
    "required",
    "error"
  ], ignore: [
    "ignore"
  ], require: [
    "required"
  ], reject: [
    "error"
  ])
          TestSerializable tm) async {
    return Response.ok(tm);
  }
}

class FilterListController extends ResourceController {
  @Operation.post()
  Future<Response> create(
      @Bind.body(accept: [
    "accept",
    "ignore",
    "required",
    "error"
  ], ignore: [
    "ignore"
  ], require: [
    "required"
  ], reject: [
    "error"
  ])
          List<TestSerializable> tm) async {
    return Response.ok(tm);
  }
}

class MapController extends ResourceController {
  @Operation.post()
  Future<Response> create(@Bind.body() Map<String, dynamic> tm) async {
    return Response.ok(tm);
  }
}

class ByteListController extends ResourceController {
  ByteListController() {
    acceptedContentTypes = [ContentType("application", "octet-stream")];
  }

  @Operation.post()
  Future<Response> create(@Bind.body() List<int> tm) async {
    return Response.ok(tm)
      ..contentType = ContentType("application", "octet-stream");
  }
}

Future<HttpServer> enableController(
    String pattern, Controller instantiate()) async {
  var router = Router();
  router.route(pattern).link(instantiate);
  router.didAddToChannel();

  var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4040);
  server.map((httpReq) => Request(httpReq)).listen(router.receive);

  return server;
}
