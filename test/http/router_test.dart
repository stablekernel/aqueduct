import 'dart:convert';
import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';

void main() {
  group("Router basics", () {
    HttpServer server;

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Router Handles Requests", () async {
      Router router = new Router();

      router.route("/player").listen((req) async {
        return new Response.ok("");
      });

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/player");
      expect(response.statusCode, equals(200));
    });

    test("Router 404s on no match", () async {
      Router router = new Router();

      router.route("/player").listen((req) async {
        return new Response.ok("");
      });

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/notplayer");
      expect(response.statusCode, equals(404));
      // No Accept header, so allow HTML
      expect(response.body, contains("<html>"));
    });

    test("Router 404 but does not accept html, no body", () async {
      Router router = new Router();

      router.route("/player").listen((req) async {
        return new Response.ok("");
      });

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/notplayer", headers: {HttpHeaders.ACCEPT: "application/json"});
      expect(response.statusCode, equals(404));
      expect(response.headers[HttpHeaders.CONTENT_TYPE], isNull);
      expect(response.body.isEmpty, true);
    });

    test("Router delivers path values", () async {
      Router router = new Router();

      router.route("/player/:id").listen((req) async {
        return new Response.ok("${req.path.variables["id"]}");
      });

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/player/foobar");
      expect(response.statusCode, equals(200));
      expect(response.body, equals('"foobar"'));
    });

    test("Base API adds to path", () async {
      var router = new Router();
      router.basePath = "/api";
      router.route("/player/").pipe(new Handler());

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/api/player");
      expect(response.statusCode, equals(202));

      response = await http.get("http://localhost:4040/player");
      expect(response.statusCode, equals(404));

      expect(router.basePath, "/api");
    });

    test("Change Base API Path after adding routes still succeeds", () async {
      var router = new Router();
      router.route("/a").pipe(new Handler());
      router.basePath = "/api";
      server = await enableRouter(router);
      var response = await http.get("http://localhost:4040/api/a");
      expect(response.statusCode, equals(202));
    });

    test("Router passes on to next request controller", () async {
      Handler.counter = 0;

      var router = new Router();
      router.route("/a").pipe(new Handler());

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
      router.route("/a/[:id]").listen((req) async {
        req.respond(new Response(200, null, null));
      });
      router.route("/a/:id/f").listen((req) async {
        req.respond(new Response(201, null, null));
      });

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/a");
      expect(response.statusCode, equals(200));

      response = await http.get("http://localhost:4040/a/1");
      expect(response.statusCode, equals(200));

      response = await http.get("http://localhost:4040/a/1/f");
      expect(response.statusCode, equals(201));
    });

    test("Base API + Route Variables correctly identifies segment", () async {
      final router = new Router()
          ..basePath = "/api/"
          ..route(("/a/[:id]")).listen((req) async => new Response.ok(req.path.variables));
      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/api/a/1");
      expect(response.statusCode, 200);
      expect(JSON.decode(response.body), {"id":"1"});

      response = await http.get("http://localhost:4040/api/a");
      expect(response.statusCode, 200);
      expect(JSON.decode(response.body), {});
    });

  });

  group("Router ordering", () {
    HttpServer server;
    var router = new Router();
    setUpAll(() async {
      router.route("/").listen((req) async {
        req.respond(new Response(200, null, "/"));
      });
      router.route("/users/[:id]").listen((req) async {
        req.respond(
            new Response(200, null, "/users/${req.path.variables["id"]}"));
      });
      router.route("/locations[/:id]").listen((req) async {
        req.respond(
            new Response(200, null, "/locations/${req.path.variables["id"]}"));
      });
      router.route("/locations/:id/vacation").listen((req) async {
        req.respond(new Response(
            200, null, "/locations/${req.path.variables["id"]}/vacation"));
      });
      router.route("/locations/:id/alarms[/*]").listen((req) async {
        req.respond(new Response(200, null,
            "/locations/${req.path.variables["id"]}/alarms/${req.path.remainingPath}"));
      });
      router.route("/equipment/[:id[/:property]]").listen((req) async {
        req.respond(new Response(200, null,
            "/equipment/${req.path.variables["id"]}/${req.path.variables["property"]}"));
      });
      router.route("/file/*").listen((req) async {
        req.respond(new Response(200, null, "/file/${req.path.remainingPath}"));
      });
      server = await enableRouter(router);
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

      response =
          await http.get("http://localhost:4040/locations/1/alarms/code");
      expect(response.body, '"/locations/1/alarms/code"');

      response = await http.get("http://localhost:4040/equipment/1/code");
      expect(response.body, '"/equipment/1/code"');
    });
  });

  group("Disambiguate *", () {
    HttpServer server;
    var router = new Router();
    setUpAll(() async {
      router.route("/*").listen((req) async => new Response.ok("*${req.path.remainingPath}"));
      router.route("/a").listen((req) async => new Response.ok("a"));

      server = await enableRouter(router);
    });

    tearDownAll(() async {
      await server?.close(force: true);
    });

    test("Disambiguate *", () async {
      var r1 = await http.get("http://localhost:4040/a");
      var r2 = await http.get("http://localhost:4040/b");
      var r3 = await http.get("http://localhost:4040/ab");
      var r4 = await http.get("http://localhost:4040/a/b");
      var r5 = await http.get("http://localhost:4040/");

      expect(r1.body, "\"a\"");
      expect(r2.body, "\"*b\"");
      expect(r3.body, "\"*ab\"");
      expect(r4.statusCode, 404);
      expect(r5.body, "\"*\"");
    });

  });
}

Future<HttpServer> enableRouter(Router router) async {
  router.prepare();
  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4040);
  server.map((httpReq) => new Request(httpReq)).listen(router.receive);
  return server;
}

class Handler extends Controller {
  static int counter = 0;

  Handler() {
    counter++;
  }

  @override
  Future<RequestOrResponse> handle(Request req) async {
    return new Response(202, null, "$counter");
  }
}
