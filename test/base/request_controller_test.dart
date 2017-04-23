import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

void main() {
  group("Outlier isolate behavior error cases", () {
    Application app;

    setUp(() async {
      app = new Application<OutlierSink>()
        ..configuration.port = 8000;
      await app.start(numberOfInstances: 1);
    });

    tearDown(() async {
      app.logger.clearListeners();
      await app.stop();
    });

    test("Logging after socket is closed throws uncaught exception, still works correctly after", () async {
      var completer = new Completer();
      app.logger.onRecord.listen((p) {
        if (p.message.contains("Uncaught exception in isolate")) {
          completer.complete();
        }
      });
      try {
        await http.get("http://localhost:8000/detach");
        expect(true, false);
      } on http.ClientException {}

      expect((await http.get("http://localhost:8000/detach")).statusCode, 200);
      expect(completer.future, completes);
    });

    test(
        "Request on bad state: header already sent is captured in RequestController",
            () async {
      var completer = new Completer();
      app.logger.onRecord.listen((p) {
        if (p.message.contains("Uncaught exception in isolate")) {
          completer.complete();
        }
      });
      expect((await http.get("http://localhost:8000/closed")).statusCode, 200);
      expect((await http.get("http://localhost:8000/closed")).statusCode, 200);
      expect(completer.future, completes);
    });

    test(
        "Request controller throwing HttpResponseException that dies on bad state: header already sent is captured in RequestController",
            () async {
      var completer = new Completer();
      app.logger.onRecord.listen((p) {
        if (p.message.contains("Uncaught exception in isolate")) {
          completer.complete();
        }
      });
      expect((await http.get("http://localhost:8000/closed_exception")).statusCode, 200);
      expect((await http.get("http://localhost:8000/closed_exception")).statusCode, 200);
      expect(completer.future, completes);
    });
  });

  group("Response error cases", () {
    HttpServer server = null;
    tearDown(() async {
      await server.close();
    });

    test("Request controller maps QueryExceptions appropriately", () async {
      var handler = (Request req) async {
        var v = int.parse(req.innerRequest.uri.queryParameters["p"]);
        switch (v) {
          case 0:
            throw new QueryException(QueryExceptionEvent.internalFailure);
          case 1:
            throw new QueryException(QueryExceptionEvent.requestFailure);
          case 2:
            throw new QueryException(QueryExceptionEvent.conflict);
          case 3:
            throw new QueryException(QueryExceptionEvent.connectionFailure);
        }

        return new Response.ok(null);
      };
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen(handler);
        await next.receive(req);
      });

      var statusCodes = (await Future.wait(
              [0, 1, 2, 3].map((p) => http.get("http://localhost:8000/?p=$p"))))
          .map((resp) => resp.statusCode)
          .toList();
      expect(statusCodes, [500, 400, 409, 503]);
    });

    test(
        "Request controller's can serialize and encode Serializable objects as JSON by default",
        () async {
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          var obj = new SomeObject()..name = "Bob";
          return new Response.ok(obj);
        });
        await next.receive(req);
      });

      var resp = await http.get("http://localhost:8081");
      expect(resp.headers["content-type"], startsWith("application/json"));
      expect(JSON.decode(resp.body), {"name": "Bob"});
    });

    test(
        "Responding to request with no content-type, but does have a body, defaults to application/json",
        () async {
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          return new Response.ok({"a": "b"});
        });
        await next.receive(req);
      });

      var resp = await http.get("http://localhost:8081");
      expect(resp.headers["content-type"], startsWith("application/json"));
      expect(JSON.decode(resp.body), {"a": "b"});
    });

    test(
        "Responding to a request with no explicit content-type and has a body that cannot be encoded to JSON will throw 500",
        () async {
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          return new Response.ok(new DateTime.now());
        });
        await next.receive(req);
      });

      var resp = await http.get("http://localhost:8081");
      expect(resp.statusCode, 500);
      expect(resp.headers["content-type"], "text/plain; charset=utf-8");
      expect(resp.body, "");
    });

    test(
        "Responding to request with no explicit content-type, but does not have a body, defaults to plaintext Content-Type header",
        () async {
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          return new Response.ok(null);
        });
        await next.receive(req);
      });
      var resp = await http.get("http://localhost:8081");
      expect(resp.statusCode, 200);
      expect(resp.headers["content-length"], "0");
      expect(resp.headers["content-type"], "text/plain; charset=utf-8");
      expect(resp.body, "");
    });

    test("Using an encoder that doesn't exist returns a 500", () async {
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          return new Response.ok(1234)
            ..contentType = new ContentType("foo", "bar", charset: "utf-8");
        });
        await next.receive(req);
      });
      var resp = await http.get("http://localhost:8081");
      var contentType = ContentType.parse(resp.headers["content-type"]);
      expect(resp.statusCode, 500);
      expect(contentType.primaryType, "application");
      expect(contentType.subType, "json");
      expect(JSON.decode(resp.body),
          {"error": "Could not encode body as foo/bar; charset=utf-8."});
    });

    test(
        "Using an encoder other than the default correctly encodes and sets content-type",
        () async {
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          return new Response.ok(1234)
            ..contentType = new ContentType("text", "plain");
        });
        await next.receive(req);
      });
      var resp = await http.get("http://localhost:8081");
      expect(resp.statusCode, 200);
      expect(resp.headers["content-type"], "text/plain");
      expect(resp.body, "1234");
    });

    test("A decoder with a match-all subtype will be used when matching",
        () async {
      Response.addEncoder(new ContentType("b", "*"), (s) => s);
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          return new Response.ok("hello")
            ..contentType = new ContentType("b", "bar", charset: "utf-8");
        });
        await next.receive(req);
      });
      var resp = await http.get("http://localhost:8081");
      expect(resp.statusCode, 200);
      expect(resp.headers["content-type"], "b/bar; charset=utf-8");
      expect(resp.body, "hello");
    });

    test(
        "A decoder with a subtype always trumps a decoder that matches any subtype",
        () async {
      Response.addEncoder(new ContentType("a", "*"), (s) => s);
      Response.addEncoder(new ContentType("a", "html"), (s) {
        return "<html>$s</html>";
      });
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          return new Response.ok("hello")
            ..contentType = new ContentType("a", "html", charset: "utf-8");
        });
        await next.receive(req);
      });
      var resp = await http.get("http://localhost:8081");
      expect(resp.statusCode, 200);
      expect(resp.headers["content-type"], "a/html; charset=utf-8");
      expect(resp.body, "<html>hello</html>");
    });

    test("Using an encoder that blows up during encoded returns 500 safely",
        () async {
      Response.addEncoder(new ContentType("foo", "bar"), (s) {
        throw new Exception("uhoh");
      });
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          return new Response.ok("hello")
            ..contentType = new ContentType("foo", "bar", charset: "utf-8");
        });
        await next.receive(req);
      });
      var resp = await http.get("http://localhost:8081");
      expect(resp.statusCode, 500);
    });

    test(
        "willSendResponse is always called prior to Response being sent for preflight requests",
        () async {
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.generate(() => new Always200Controller());
        await next.receive(req);
      });

      // Invalid preflight
      var req = await (new HttpClient().open("OPTIONS", "localhost", 8081, ""));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers", "accept, authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(JSON.decode((new String.fromCharCodes(await resp.first))),
          {"statusCode": 403});

      // valid preflight
      req = await (new HttpClient().open("OPTIONS", "localhost", 8081, ""));
      req.headers.set("Origin", "http://somewhere.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers", "accept, authorization");
      resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(JSON.decode((new String.fromCharCodes(await resp.first))),
          {"statusCode": 200});
    });

    test(
        "willSendResponse is always called prior to Response being sent for normal requests",
        () async {
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.generate(() => new Always200Controller());
        await next.receive(req);
      });

      // normal response
      var resp = await http.get("http://localhost:8081");
      expect(resp.statusCode, 200);
      expect(JSON.decode(resp.body), {"statusCode": 100});

      // httpresponseexception
      resp = await http.get("http://localhost:8081?q=http_response_exception");
      expect(resp.statusCode, 200);
      expect(JSON.decode(resp.body), {"statusCode": 400});

      // query exception
      resp = await http.get("http://localhost:8081?q=query_exception");
      expect(resp.statusCode, 200);
      expect(JSON.decode(resp.body), {"statusCode": 503});

      // any other exception (500)
      resp = await http.get("http://localhost:8081?q=server_error");
      expect(resp.statusCode, 200);
      expect(JSON.decode(resp.body), {"statusCode": 500});
    });

    test("Failure to decode request body as appropriate type is 400", () async {
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((r) async {
          await r.body.decodeAsMap();
          return new Response.ok(null);
        });
        await next.receive(req);
      });

      var resp = await http.post("http://localhost:8081", headers: {
        "content-type": "application/json"
      }, body: JSON.encode(["a"]));

      expect(resp.statusCode, 400);
    });
  });
}

class SomeObject implements HTTPSerializable {
  String name;

  Map<String, dynamic> asSerializable() {
    return {"name": name};
  }
}

class Always200Controller extends RequestController {
  Always200Controller() {
    policy.allowedOrigins = ["http://somewhere.com"];
  }
  @override
  Future<RequestOrResponse> processRequest(Request req) async {
    var q = req.innerRequest.uri.queryParameters["q"];
    if (q == "http_response_exception") {
      throw new HTTPResponseException(400, "ok");
    } else if (q == "query_exception") {
      throw new QueryException(QueryExceptionEvent.connectionFailure);
    } else if (q == "server_error") {
      throw new FormatException("whocares");
    }
    return new Response(100, null, null);
  }

  @override
  void willSendResponse(Response resp) {
    var originalMap = {"statusCode": resp.statusCode};
    resp.statusCode = 200;
    resp.body = originalMap;
    resp.contentType = ContentType.JSON;
  }
}

class OutlierSink extends RequestSink {
  OutlierSink(ApplicationConfiguration config) : super(config);
  int count = 0;

  @override
  void setupRouter(Router r) {
    r.route("/detach").listen((Request req) async {
      if (count == 0) {
        var socket = await req.innerRequest.response.detachSocket();
        socket.destroy();

        req.toDebugString(
            includeHeaders: true,
            includeBody: true,
            includeContentSize: true,
            includeElapsedTime: true,
            includeMethod: true,
            includeRequestIP: true,
            includeResource: true,
            includeStatusCode: true);
      }

      count ++;

      return new Response.ok(null);
    });

    r.route("/closed").listen((Request req) async {
      if (count == 0) {
        req.innerRequest.response.statusCode = 200;
        await req.response.close();
      }

      count ++;

      return new Response.ok(null);
    });

    r.route("/closed_exception").listen((Request req) async {
      await req.response.close();

      // To stop the analyzer from complaining, since it see through the bullshit of 'if (true)' and the return type would be dead code.
      if ([1].any((i) => true)) {
        throw new HTTPResponseException(400, "whocares");
      }
      return new Response.ok(null);
    });
  }
}