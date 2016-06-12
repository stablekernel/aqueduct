@TestOn("vm")
import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';


void main() {
  HttpServer server = null;

  tearDown(() async {
    await server?.close(force: true);
  });

  test("Router Handles Requests", () async {
    Router router = new Router();

    router.route("/player").then(new RequestHandler(requestHandler: (req) {
      return new Response.ok("");
    }));

    server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/player");
    expect(response.statusCode, equals(200));
  });

  test("Router 404s on no match", () async {
    Router router = new Router();

    router.route("/player").then(new RequestHandler(requestHandler: (req) {
      return new Response.ok("");
    }));

    server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/notplayer");
    expect(response.statusCode, equals(404));
  });

  test("Router delivers path values", () async {
    Router router = new Router();

    router.route("/player/:id").then(new RequestHandler(requestHandler: (req) {
      return new Response.ok("${req.path.variables["id"]}");
    }));

    server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/player/foobar");
    expect(response.statusCode, equals(200));
    expect(response.body, equals('"foobar"'));
  });

  test("Base API Path Throws exception when adding routes prior to setting it", () async {
    var router = new Router();
    router.route("/a");

    var successful = false;
    try {
      router.basePath = "/api";
      successful = true;
    } catch (e) {
      expect(e is Exception, true);
    }
    expect(successful, false);
  });

  test("Base API adds to path", () async {
    var router = new Router();
    router.basePath = "/api";
    router.route("/player/").then(new Handler());

    server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/api/player");
    expect(response.statusCode, equals(202));

    response = await http.get("http://localhost:4040/player");
    expect(response.statusCode, equals(404));
  });

  test("Router uses request handlers", () async {
    Handler.counter = 0;

    var router = new Router();
    router.route("/a").then(new Handler());

    server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/a");
    expect(response.statusCode, equals(202));
    expect(response.body, '"1"');

    response = await http.get("http://localhost:4040/a");
    expect(response.statusCode, equals(202));
    expect(response.body, '"1"');
  });

  test("Router uses request handler generators", () async {
    Handler.counter = 0;

    var router = new Router();
    router.route("/a").then(() => new Handler());
    server = await enableRouter(router);

    for (int i = 0; i < 10; i++) {
      var response = await http.get("http://localhost:4040/a");
      expect(response.statusCode, equals(202));
      expect(response.body, '"${i + 1}"');
    }
  });
}


Future<HttpServer> enableRouter(Router router) async {
  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4040);
  server.map((httpReq) => new ResourceRequest(httpReq)).listen(router.deliver);
  return server;
}

class Handler extends RequestHandler {
  static int counter = 0;

  Handler() {
    counter ++;
  }

  @override
  Future<RequestHandlerResult> processRequest(ResourceRequest req) async {
    return new Response(202, null, "$counter");
  }
}