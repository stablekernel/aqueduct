@TestOn("vm")

import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'dart:async';
import 'package:http/http.dart' as http;
import '../lib/monadart.dart';


void main() {

  setUp(() {

  });

  tearDown(() {
  });

  test("Router Handles Requests", () async {
    Router router = new Router();
    router.addRoute("/player").listen((req) {
      req.respond(new Response.ok(""));
    });

    var server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/player");
    expect(response.statusCode, equals(200));

    server.close(force: true);
  });

  test("Router 404s on no match", () async {
    Router router = new Router();
    router.addRoute("/player").listen((req) {
      req.respond(new Response.ok(""));
    });

    var server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/notplayer");
    expect(response.statusCode, equals(404));

    server.close(force: true);
  });

  test("Router delivers path values", () async {
    Router router = new Router();
    router.addRoute("/player/:id").listen((req) {
      req.respond(new Response.ok("${req.pathParameters["id"]}"));
    });

    var server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/player/foobar");
    expect(response.statusCode, equals(200));
    expect(response.body, equals("foobar"));

    server.close(force: true);
  });

  test("Base API Path Throws exception when adding routes prior to setting it", () async {
    var router = new Router();
    router.addRoute("/a");

    try {
      router.basePath = "/api";
      fail("This should fail");
    } catch (e) {
      expect(e is Exception, true);
    }
  });

  test("Base API adds to path", () async {
    var router = new Router();
    router.basePath = "/api";
    router.addRoute("/player/").listen((req) {
      req.respond(new Response.ok(""));
    });

    var server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/api/player");
    expect(response.statusCode, equals(200));

    response = await http.get("http://localhost:4040/player");
    expect(response.statusCode, equals(404));

    server.close(force: true);
  });

  test("Router uses request handlers", () async {
    var router = new Router();
    router.addRouteHandler("/a", new Handler());

    var server = await enableRouter(router);

    var response = await http.get("http://localhost:4040/a");
    expect(response.statusCode, equals(202));
    expect(response.body, "1");

    response = await http.get("http://localhost:4040/a");
    expect(response.statusCode, equals(202));
    expect(response.body, "1");


    server.close(force: true);
  });

  test("Router uses request handler generators", () async {
    var router = new Router();
    router.addRouteHandler("/a", new RequestHandlerGenerator<Handler>());
    var server = await enableRouter(router);

    Handler.counter = 0;

    for(int i = 0; i < 10; i++) {
      var response = await http.get("http://localhost:4040/a");
      expect(response.statusCode, equals(202));
      expect(response.body, "${i + 1}");
    }

    server.close(force: true);
  });
}


Future<HttpServer> enableRouter(Router router) async {
  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4040);
  server.map((httpReq) => new ResourceRequest(httpReq)).listen(router.handleRequest);
  return server;
}

class Handler extends RequestHandler {
  static int counter = 0;

  Handler() {
    counter ++;
  }

  void handleRequest(ResourceRequest req) {
    req.respond(new Response(202, null, "$counter"));
  }
}