import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  group("Linking", () {
    HttpServer server;

    tearDown(() async {
      await server?.close();
    });

    test("Prepare flows through controllers", () async {
      final completer = Completer();
      final root = PassthruController();
      root
          .linkFunction((req) async => req)
          .link(() => Always200Controller())
          .link(() => PrepareTailController(completer));
      root.didAddToChannel();
      expect(completer.future, completes);
    });
  });

  group("Response modifiers", () {
    HttpServer server;
    Controller root;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4111);
      root = PassthruController();
      server.map((r) => Request(r)).listen((req) {
        root.receive(req);
      });
    });

    tearDown(() async {
      await server.close();
    });

    test("Can add change status code", () async {
      root.linkFunction((r) async {
        return r..addResponseModifier((resp) => resp.statusCode = 201);
      }).linkFunction((r) async {
        return Response.ok(null);
      });

      var resp = await http.get("http://localhost:4111/");
      expect(resp.statusCode, 201);
    });

    test("Can remove header", () async {
      root.linkFunction((r) async {
        return r..addResponseModifier((resp) => resp.headers.remove("x-foo"));
      }).linkFunction((r) async {
        return Response.ok(null, headers: {"x-foo": "foo"});
      });

      var resp = await http.get("http://localhost:4111/");
      expect(resp.headers.containsKey("x-foo"), false);
    });

    test("Can add header", () async {
      root.linkFunction((r) async {
        return r..addResponseModifier((resp) => resp.headers["x-foo"] = "bar");
      }).linkFunction((r) async {
        return Response.ok(null);
      });

      var resp = await http.get("http://localhost:4111/");
      expect(resp.headers["x-foo"], "bar");
    });

    test("Can change header value", () async {
      root.linkFunction((r) async {
        return r..addResponseModifier((resp) => resp.headers["x-foo"] = "bar");
      }).linkFunction((r) async {
        return Response.ok(null, headers: {"x-foo": "foo"});
      });

      var resp = await http.get("http://localhost:4111/");
      expect(resp.headers["x-foo"], "bar");
    });

    test("Can modify body prior to encoding", () async {
      root.linkFunction((r) async {
        return r..addResponseModifier((resp) => resp.body["foo"] = "y");
      }).linkFunction((r) async {
        return Response.ok({"x": "a"});
      });

      var resp = await http.get("http://localhost:4111/");
      expect(json.decode(resp.body), {"foo": "y", "x": "a"});
    });

    test(
        "Response modifier that throws uncaught exception sends 500 server error",
        () async {
      root.linkFunction((r) async {
        return r..addResponseModifier((resp) => throw Exception('expected'));
      }).linkFunction((r) async {
        return Response.ok(null);
      });

      var resp = await http.get("http://localhost:4111/");
      expect(resp.statusCode, 500);
    });
  });

  group("Can return null from request controller is valid", () {
    HttpServer server;
    Controller root;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4111);
      root = PassthruController();

      server.map((r) => Request(r)).listen((req) {
        root.receive(req);
      });
    });

    tearDown(() async {
      await server.close();
    });

    test("Return null", () async {
      var set = false;
      root.linkFunction((req) {
        req.raw.response.statusCode = 200;
        req.raw.response.close();

        return null;
      }).linkFunction(
          // ignore: missing_return
          (req) {
        set = true;
      });

      var response = await http.get("http://localhost:4111");
      expect(response.statusCode, 200);
      expect(set, false);
    });
  });

  group("Outlier isolate behavior error cases", () {
    Application app;

    setUp(() async {
      app = Application<OutlierChannel>()..options.port = 8000;
      await app.start(numberOfInstances: 1);
    });

    tearDown(() async {
      app.logger.clearListeners();
      await app.stop();
    });

    test(
        "Logging after socket is closed throws uncaught exception, still works correctly after",
        () async {
          final request = await HttpClient().get("localhost", 8000, "/detach");
          final response = await request.close();
      try {
        await response.toList();
        expect(true, false);
        // ignore: empty_catches
      } on HttpException {}

      expect((await http.get("http://localhost:8000/detach")).statusCode, 200);
    });

    test("Request on bad state: header already sent is captured in Controller",
        () async {
      expect((await http.get("http://localhost:8000/closed")).statusCode, 200);
      expect((await http.get("http://localhost:8000/closed")).statusCode, 200);
    });

    test(
        "Request controller throwing HttpResponseException that dies on bad state: header already sent is captured in Controller",
        () async {
      expect(
          (await http.get("http://localhost:8000/closed_exception")).statusCode,
          200);
      expect(
          (await http.get("http://localhost:8000/closed_exception")).statusCode,
          200);
    });
  });

  group("Response error cases", () {
    HttpServer server;
    tearDown(() async {
      await server.close();
    });

    test(
        "Request controller's can serialize and encode Serializable objects as JSON by default",
        () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      server.map((req) => Request(req)).listen((req) async {
        var next = PassthruController();
        next.linkFunction((req) async {
          var obj = SomeObject()..name = "Bob";
          return Response.ok(obj);
        });
        await next.receive(req);
      });

      var resp = await http.get("http://localhost:8888");
      expect(resp.headers["content-type"], startsWith("application/json"));
      expect(json.decode(resp.body), {"name": "Bob"});
    });

    test(
        "Responding to request with no content-type, but does have a body, defaults to application/json",
        () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      server.map((req) => Request(req)).listen((req) async {
        var next = PassthruController();
        next.linkFunction((req) async {
          return Response.ok({"a": "b"});
        });
        await next.receive(req);
      });

      var resp = await http.get("http://localhost:8888");
      expect(resp.headers["content-type"], startsWith("application/json"));
      expect(json.decode(resp.body), {"a": "b"});
    });

    test(
        "Responding to a request with no explicit content-type and has a body that cannot be encoded to JSON will throw 500",
        () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      server.map((req) => Request(req)).listen((req) async {
        var next = PassthruController();
        next.linkFunction((req) async {
          return Response.ok(DateTime.now());
        });
        await next.receive(req);
      });

      var resp = await http.get("http://localhost:8888");
      expect(resp.statusCode, 500);
      expect(resp.headers["content-type"], isNull);
      expect(resp.body.isEmpty, true);
    });

    test(
        "Responding to request with no explicit content-type, does not have a body, has no content-type",
        () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      server.map((req) => Request(req)).listen((req) async {
        var next = PassthruController();
        next.linkFunction((req) async {
          return Response.ok(null);
        });
        await next.receive(req);
      });
      var resp = await http.get("http://localhost:8888");
      expect(resp.statusCode, 200);
      expect(resp.headers["content-length"], "0");
      expect(resp.headers["content-type"], isNull);
      expect(resp.body.isEmpty, true);
    });

    test(
        "willSendResponse is always called prior to Response being sent for preflight requests",
        () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      server.map((req) => Request(req)).listen((req) async {
        var next = PassthruController();
        next.link(() => Always200Controller());
        await next.receive(req);
      });

      // Invalid preflight
      var req = await HttpClient().open("OPTIONS", "localhost", 8888, "");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers
          .set("Access-Control-Request-Headers", "accept, authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(json.decode(String.fromCharCodes(await resp.first)),
          {"statusCode": 403});

      // valid preflight
      req = await HttpClient().open("OPTIONS", "localhost", 8888, "");
      req.headers.set("Origin", "http://somewhere.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers
          .set("Access-Control-Request-Headers", "accept, authorization");
      resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(json.decode(String.fromCharCodes(await resp.first)),
          {"statusCode": 200});
    });

    test(
        "willSendResponse is always called prior to Response being sent for normal requests",
        () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      server.map((req) => Request(req)).listen((req) async {
        var next = PassthruController();
        next.link(() => Always200Controller());
        await next.receive(req);
      });

      // normal response
      var resp = await http.get("http://localhost:8888");
      expect(resp.statusCode, 200);
      expect(json.decode(resp.body), {"statusCode": 100});

      // httpresponseexception
      resp = await http.get("http://localhost:8888?q=http_response_exception");
      expect(resp.statusCode, 200);
      expect(json.decode(resp.body), {"statusCode": 400});

      // query exception
      resp = await http.get("http://localhost:8888?q=query_exception");
      expect(resp.statusCode, 200);
      expect(json.decode(resp.body), {"statusCode": 503});

      // any other exception (500)
      resp = await http.get("http://localhost:8888?q=server_error");
      expect(resp.statusCode, 200);
      expect(json.decode(resp.body), {"statusCode": 500});
    });

    test("Failure to decode request body as appropriate type is 400", () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      server.map((req) => Request(req)).listen((req) async {
        var next = PassthruController();
        next.linkFunction((r) async {
          await r.body.decode<Map<String, dynamic>>();
          return Response.ok(null);
        });
        await next.receive(req);
      });

      var resp = await http.post("http://localhost:8888",
          headers: {"content-type": "application/json"},
          body: json.encode(["a"]));

      expect(resp.statusCode, 400);
    });
  });
}

class SomeObject extends Serializable {
  String name;

  @override
  void readFromMap(dynamic any) {}

  @override
  Map<String, dynamic> asMap() {
    return {"name": name};
  }
}

class Always200Controller extends Controller {
  Always200Controller() {
    policy.allowedOrigins = ["http://somewhere.com"];
  }

  @override
  Future<RequestOrResponse> handle(Request req) async {
    var q = req.raw.uri.queryParameters["q"];
    if (q == "http_response_exception") {
      throw Response.badRequest(body: {"error": "ok"});
    } else if (q == "query_exception") {
      throw QueryException(QueryExceptionEvent.transport);
    } else if (q == "server_error") {
      throw const FormatException("whocares");
    }
    return Response(100, null, null);
  }

  @override
  void willSendResponse(Response resp) {
    var originalMap = {"statusCode": resp.statusCode};
    resp.statusCode = 200;
    resp.body = originalMap;
    resp.contentType = ContentType.json;
  }
}

class OutlierChannel extends ApplicationChannel {
  int count = 0;

  @override
  Controller get entryPoint {
    final r = Router();
    r.route("/detach").linkFunction((Request req) async {
      if (count == 0) {
        var socket = await req.raw.response.detachSocket();
        socket.destroy();

        req.toDebugString(
            includeHeaders: true,
            includeContentSize: true,
            includeElapsedTime: true,
            includeMethod: true,
            includeRequestIP: true,
            includeResource: true,
            includeStatusCode: true);
      }

      count++;

      return Response.ok(null);
    });

    r.route("/closed").linkFunction((Request req) async {
      if (count == 0) {
        req.raw.response.statusCode = 200;
        await req.response.close();
      }

      count++;

      return Response.ok(null);
    });

    r.route("/closed_exception").linkFunction((Request req) async {
      await req.response.close();

      // To stop the analyzer from complaining, since it see through the bullshit of 'if (true)' and the return type would be dead code.
      if ([1].any((i) => true)) {
        throw Response.badRequest(body: {"error": "whocares"});
      }
      return Response.ok(null);
    });
    return r;
  }
}

class PrepareTailController extends Controller {
  PrepareTailController(this.completer);

  final Completer completer;

  @override
  void didAddToChannel() {
    completer.complete();
  }

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return request;
  }
}
