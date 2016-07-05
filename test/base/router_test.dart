import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';

// Add to make sure variables and remaining path get stuffed into PathRequest


void main() {
  group("Router basics", () {
    HttpServer server = null;

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Router Handles Requests", () async {
      Router router = new Router();

      router.route("/player").next(new RequestHandler(requestHandler: (req) {
        return new Response.ok("");
      }));

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/player");
      expect(response.statusCode, equals(200));
    });

    test("Router 404s on no match", () async {
      Router router = new Router();

      router.route("/player").next(new RequestHandler(requestHandler: (req) {
        return new Response.ok("");
      }));

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/notplayer");
      expect(response.statusCode, equals(404));
    });

    test("Router delivers path values", () async {
      Router router = new Router();

      router.route("/player/:id").next(new RequestHandler(requestHandler: (req) {
        return new Response.ok("${req.path.variables["id"]}");
      }));

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/player/foobar");
      expect(response.statusCode, equals(200));
      expect(response.body, equals('"foobar"'));
    });

    test("Base API adds to path", () async {
      var router = new Router();
      router.basePath = "/api";
      router.route("/player/").next(new Handler());

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/api/player");
      expect(response.statusCode, equals(202));

      response = await http.get("http://localhost:4040/player");
      expect(response.statusCode, equals(404));
    });

    test("Change Base API Path after adding routes still succeeds", () async {
      var router = new Router();
      router.route("/a").next(new Handler());
      router.basePath = "/api";
      server = await enableRouter(router);
      var response = await http.get("http://localhost:4040/api/a");
      expect(response.statusCode, equals(202));
    });

    test("Router passes on to next request handler", () async {
      Handler.counter = 0;

      var router = new Router();
      router.route("/a").next(new Handler());

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/a");
      expect(response.statusCode, equals(202));
      expect(response.body, '"1"');

      response = await http.get("http://localhost:4040/a");
      expect(response.statusCode, equals(202));
      expect(response.body, '"1"');
    });

    test("Router matches right route when many are similar", () async {
      var router = new Router();
      router.route("/a/[:id]").next(new RequestHandler(requestHandler: (Request req) {
        req.respond(new Response(200, null, null));
      }));
      router.route("/a/:id/f").next(new RequestHandler(requestHandler: (Request req) {
        req.respond(new Response(201, null, null));
      }));

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/a");
      expect(response.statusCode, equals(200));

      response = await http.get("http://localhost:4040/a/1");
      expect(response.statusCode, equals(200));

      response = await http.get("http://localhost:4040/a/1/f");
      expect(response.statusCode, equals(201));
    });
  });

  group("Router ordering", () {
    HttpServer server = null;
    var router = new Router();
    setUpAll(() async {
      router.route("/").next(new RequestHandler(requestHandler: (Request req) {
        req.respond(new Response(200, null, "/"));
      }));
      router.route("/users/[:id]").next(new RequestHandler(requestHandler: (Request req) {
        req.respond(new Response(200, null, "/users/${req.path.variables["id"]}"));
      }));
      router.route("/locations[/:id]").next(new RequestHandler(requestHandler: (Request req) {
        req.respond(new Response(200, null, "/locations/${req.path.variables["id"]}"));
      }));
      router.route("/locations/:id/vacation").next(new RequestHandler(requestHandler: (Request req) {
        req.respond(new Response(200, null, "/locations/${req.path.variables["id"]}/vacation"));
      }));
      router.route("/locations/:id/alarms[/*]").next(new RequestHandler(requestHandler: (Request req) {
        req.respond(new Response(200, null, "/locations/${req.path.variables["id"]}/alarms/${req.path.remainingPath}"));
      }));
      router.route("/equipment/[:id[/:property]]").next(new RequestHandler(requestHandler: (Request req) {
        req.respond(new Response(200, null, "/equipment/${req.path.variables["id"]}/${req.path.variables["property"]}"));
      }));
      router.route("/file/*").next(new RequestHandler(requestHandler: (Request req) {
        req.respond(new Response(200, null, "/file/${req.path.remainingPath}"));
      }));
      await enableRouter(router);
    });

    tearDownAll(() async {
      await server?.close(force: true);
    });

    test("Empty", () async {
      var response = await http.get("http://localhost:4040");
      expect(response.body, '"/"');
      response = await http.get("http://localhost:4040/");
      expect(response.body, '"/"');
    });

    test("Root level items", () async {
      var response = await http.get("http://localhost:4040/users");
      expect(response.body, '"/users/null"');

      response = await http.get("http://localhost:4040/locations");
      expect(response.body, '"/locations/null"');

      response = await http.get("http://localhost:4040/equipment");
      expect(response.body, '"/equipment/null/null"');

      response = await http.get("http://localhost:4040/file");
      expect(response.statusCode, 404);
    });

    test("2nd level items", () async {
      var response = await http.get("http://localhost:4040/users/1");
      expect(response.body, '"/users/1"');

      response = await http.get("http://localhost:4040/locations/1");
      expect(response.body, '"/locations/1"');

      response = await http.get("http://localhost:4040/equipment/1");
      expect(response.body, '"/equipment/1/null"');

      response = await http.get("http://localhost:4040/file/1");
      expect(response.body, '"/file/1"');

      response = await http.get("http://localhost:4040/file/1/2/3");
      expect(response.body, '"/file/1/2/3"');
    });

    test("3rd level items", () async {
      var response = await http.get("http://localhost:4040/users/1/vacation");
      expect(response.statusCode, 404);

      response = await http.get("http://localhost:4040/locations/1/vacation");
      expect(response.body, '"/locations/1/vacation"');

      response = await http.get("http://localhost:4040/locations/1/alarms");
      expect(response.body, '"/locations/1/alarms/null"');

      response = await http.get("http://localhost:4040/locations/1/alarms/code");
      expect(response.body, '"/locations/1/alarms/code"');

      response = await http.get("http://localhost:4040/equipment/1/code");
      expect(response.body, '"/equipment/1/code"');
    });
  });
}


Future<HttpServer> enableRouter(Router router) async {
  router.finalize();
  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4040);
  server.map((httpReq) => new Request(httpReq)).listen(router.deliver);
  return server;
}

class Handler extends RequestHandler {
  static int counter = 0;

  Handler() {
    counter ++;
  }

  @override
  Future<RequestHandlerResult> processRequest(Request req) async {
    return new Response(202, null, "$counter");
  }
}