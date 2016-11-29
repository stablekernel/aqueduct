import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

void main() {
  HttpServer server = null;
  tearDown(() async {
    await server.close();
  });

  test("Logging after socket is closed does not throw exception", () async {
    var handler = (Request req) async {
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

      return new Response.ok(null);
    };

    var ensureExceptionIsCapturedByDeliver = new Completer();
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen(handler);

      await next.receive(req);

      // We'll get here only if delivery succeeds, evne tho the response must be an error
      ensureExceptionIsCapturedByDeliver.complete(true);
    });

    try {
      await http.get("http://localhost:8000");
    } catch (e) {}

    expect(ensureExceptionIsCapturedByDeliver.future, completes);
  });

  test(
      "Request controller that dies on bad state: header already sent is captured in RequestController",
      () async {
    var handler = (Request req) async {
      await req.response.close();

      return new Response.ok(null);
    };

    var ensureExceptionIsCapturedByDeliver = new Completer();
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen(handler);
      await next.receive(req);
      // We won't get here unless an exception is thrown, and that's what we're testing
      ensureExceptionIsCapturedByDeliver.complete(true);
    });

    await http.get("http://localhost:8000");

    expect(ensureExceptionIsCapturedByDeliver.future, completes);
  });

  test(
      "Request controller throwing HttpResponseException that dies on bad state: header already sent is captured in RequestController",
      () async {
    var handler = (Request req) async {
      await req.response.close();

      // To stop the analyzer from complaining, since it see through the bullshit of 'if (true)' and the return type would be dead code.
      if ([1].any((i) => true)) {
        throw new HTTPResponseException(400, "whocares");
      }
      return new Response.ok(null);
    };

    var ensureExceptionIsCapturedByDeliver = new Completer();
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen(handler);
      await next.receive(req);
      // We won't get here unless an exception is thrown, and that's what we're testing
      ensureExceptionIsCapturedByDeliver.complete(true);
    });

    await http.get("http://localhost:8000");

    expect(ensureExceptionIsCapturedByDeliver.future, completes);
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
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen((req) async {
        var obj = new SomeObject()..name = "Bob";
        return new Response.ok(obj);
      });
      await next.receive(req);
    });

    var resp = await http.get("http://localhost:8080");
    expect(resp.headers["content-type"], startsWith("application/json"));
    expect(JSON.decode(resp.body), {"name": "Bob"});
  });

  test(
      "Responding to request with no content-type, but does have a body, defaults to application/json",
      () async {
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen((req) async {
        return new Response.ok({"a": "b"});
      });
      await next.receive(req);
    });

    var resp = await http.get("http://localhost:8080");
    expect(resp.headers["content-type"], startsWith("application/json"));
    expect(JSON.decode(resp.body), {"a": "b"});
  });

  test(
      "Responding to a request with no explicit content-type and has a body that cannot be encoded to JSON will throw 500",
      () async {
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen((req) async {
        return new Response.ok(new DateTime.now());
      });
      await next.receive(req);
    });

    var resp = await http.get("http://localhost:8080");
    expect(resp.statusCode, 500);
    expect(resp.headers["content-type"], "text/plain; charset=utf-8");
    expect(resp.body, "");
  });

  test(
      "Responding to request with no explicit content-type, but does not have a body, defaults to plaintext Content-Type header",
      () async {
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen((req) async {
        return new Response.ok(null);
      });
      await next.receive(req);
    });
    var resp = await http.get("http://localhost:8080");
    expect(resp.statusCode, 200);
    expect(resp.headers["content-length"], "0");
    expect(resp.headers["content-type"], "text/plain; charset=utf-8");
    expect(resp.body, "");
  });

  test("Using an encoder that doesn't exist returns a 500", () async {
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen((req) async {
        return new Response.ok(1234)
          ..contentType = new ContentType("foo", "bar", charset: "utf-8");
      });
      await next.receive(req);
    });
    var resp = await http.get("http://localhost:8080");
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
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen((req) async {
        return new Response.ok(1234)
          ..contentType = new ContentType("text", "plain");
      });
      await next.receive(req);
    });
    var resp = await http.get("http://localhost:8080");
    expect(resp.statusCode, 200);
    expect(resp.headers["content-type"], "text/plain");
    expect(resp.body, "1234");
  });

  test("A decoder with a match-all subtype will be used when matching",
      () async {
    Response.addEncoder(new ContentType("b", "*"), (s) => s);
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen((req) async {
        return new Response.ok("hello")
          ..contentType = new ContentType("b", "bar", charset: "utf-8");
      });
      await next.receive(req);
    });
    var resp = await http.get("http://localhost:8080");
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
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen((req) async {
        return new Response.ok("hello")
          ..contentType = new ContentType("a", "html", charset: "utf-8");
      });
      await next.receive(req);
    });
    var resp = await http.get("http://localhost:8080");
    expect(resp.statusCode, 200);
    expect(resp.headers["content-type"], "a/html; charset=utf-8");
    expect(resp.body, "<html>hello</html>");
  });

  test("Using an encoder that blows up during encoded returns 500 safely",
      () async {
    Response.addEncoder(new ContentType("foo", "bar"), (s) {
      throw new Exception("uhoh");
    });
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    server.map((req) => new Request(req)).listen((req) async {
      var next = new RequestController();
      next.listen((req) async {
        return new Response.ok("hello")
          ..contentType = new ContentType("foo", "bar", charset: "utf-8");
      });
      await next.receive(req);
    });
    var resp = await http.get("http://localhost:8080");
    expect(resp.statusCode, 500);
  });
}

class SomeObject implements HTTPSerializable {
  String name;

  Map<String, dynamic> asSerializable() {
    return {"name": name};
  }
}
