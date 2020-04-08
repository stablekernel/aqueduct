import 'dart:async';
import 'dart:convert';
import "dart:core";
import "dart:io";

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import "package:test/test.dart";

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  group("Router basics", () {
    HttpServer server;

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Router Handles Requests", () async {
      Router router = Router();

      router.route("/player").linkFunction((req) async {
        return Response.ok("");
      });

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/player");
      expect(response.statusCode, equals(200));
    });

    test("Router 404s on no match", () async {
      Router router = Router();

      router.route("/player").linkFunction((req) async {
        return Response.ok("");
      });

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/notplayer");
      expect(response.statusCode, equals(404));
      // No Accept header, so allow HTML
      expect(response.body, contains("<html>"));
    });

    test("Router 404 but does not accept html, no body", () async {
      Router router = Router();

      router.route("/player").linkFunction((req) async {
        return Response.ok("");
      });

      server = await enableRouter(router);

      var response =
          await http.get("http://localhost:4040/notplayer", headers: {HttpHeaders.acceptHeader: "application/json"});
      expect(response.statusCode, equals(404));
      expect(response.headers[HttpHeaders.contentTypeHeader], isNull);
      expect(response.body.isEmpty, true);
    });

    test("Router delivers path values", () async {
      Router router = Router();

      router.route("/player/:id").linkFunction((req) async {
        return Response.ok("${req.path.variables["id"]}");
      });

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/player/foobar");
      expect(response.statusCode, equals(200));
      expect(response.body, equals('"foobar"'));
    });

    test("Base API adds to path", () async {
      var router = Router(basePath: "/api");
      router.route("/player/").link(() => Handler());

      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/api/player");
      expect(response.statusCode, equals(202));

      response = await http.get("http://localhost:4040/player");
      expect(response.statusCode, equals(404));

      expect(router.basePath, "/api");
    });

    test("Change Base API Path after adding routes still succeeds", () async {
      var router = Router(basePath: "/api");
      router.route("/a").link(() => Handler());
      server = await enableRouter(router);
      var response = await http.get("http://localhost:4040/api/a");
      expect(response.statusCode, equals(202));
    });

    test("Router matches right route when many are similar", () async {
      var router = Router();
      router.route("/a/[:id]").linkFunction((req) async {
        // ignore: unawaited_futures
        req.respond(Response(200, null, null));
        return null;
      });
      router.route("/a/:id/f").linkFunction((req) async {
        // ignore: unawaited_futures
        req.respond(Response(201, null, null));
        return null;
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
      final router = Router(basePath: "/api/")
        ..route("/a/[:id]").linkFunction((req) async => Response.ok(req.path.variables));
      server = await enableRouter(router);

      var response = await http.get("http://localhost:4040/api/a/1");
      expect(response.statusCode, 200);
      expect(json.decode(response.body), {"id": "1"});

      response = await http.get("http://localhost:4040/api/a");
      expect(response.statusCode, 200);
      expect(json.decode(response.body), {});
    });
  });

  group("Router ordering", () {
    HttpServer server;
    var router = Router();
    setUpAll(() async {
      router.route("/").linkFunction((req) async {
        return Response(200, null, "/");
      });
      router.route("/users/[:id]").linkFunction((req) async {
        return Response(200, null, "/users/${req.path.variables["id"]}");
      });
      router.route("/locations[/:id]").linkFunction((req) async {
        return Response(200, null, "/locations/${req.path.variables["id"]}");
      });
      router.route("/locations/:id/vacation").linkFunction((req) async {
        return Response(200, null, "/locations/${req.path.variables["id"]}/vacation");
      });
      router.route("/locations/:id/alarms[/*]").linkFunction((req) async {
        return Response(200, null, "/locations/${req.path.variables["id"]}/alarms/${req.path.remainingPath}");
      });
      router.route("/equipment/[:id[/:property]]").linkFunction((req) async {
        return Response(200, null, "/equipment/${req.path.variables["id"]}/${req.path.variables["property"]}");
      });
      router.route("/file/*").linkFunction((req) async {
        return Response(200, null, "/file/${req.path.remainingPath}");
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

      response = await http.get("http://localhost:4040/locations/1/alarms/code");
      expect(response.body, '"/locations/1/alarms/code"');

      response = await http.get("http://localhost:4040/equipment/1/code");
      expect(response.body, '"/equipment/1/code"');
    });
  });

  group("Disambiguate *", () {
    HttpServer server;
    var router = Router();
    setUpAll(() async {
      router.route("/*").linkFunction((req) async => Response.ok("*${req.path.remainingPath}"));
      router.route("/a").linkFunction((req) async => Response.ok("a"));

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

  group("Controller linking", () {
    HttpServer server;

    tearDown(() async {
      await server?.close();
    });

    test("Router can be linked to", () async {
      final root = PassthruController();
      final router = Router()..route("/1").link(() => NumberEmitter(1))..route("/2").link(() => NumberEmitter(2));

      root.link(() => router);

      root.didAddToChannel();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4040);
      server.map((httpReq) => Request(httpReq)).listen(root.receive);

      expect((await http.get("http://localhost:4040/1")).body, "1");
      expect((await http.get("http://localhost:4040/2")).body, "2");
    });

    test("Router delivers prepare to all controllers", () async {
      Completer c1 = Completer();
      Completer c2 = Completer();
      final root = OKController();
      final router = Router()
        ..route("/a").link(() => PrepareTailController(c1))
        ..route("/b").link(() => PrepareTailController(c2));

      root.link(() => router);

      root.didAddToChannel();
      expect(c1.future, completes);
      expect(c2.future, completes);
    });
  });
}

Future<HttpServer> enableRouter(Router router) async {
  router.didAddToChannel();
  var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4040);
  server.map((httpReq) => Request(httpReq)).listen(router.receive);
  return server;
}

class Handler extends Controller {
  @override
  Future<RequestOrResponse> handle(Request req) async {
    return Response(202, null, "ok");
  }
}

class NumberEmitter extends Controller {
  NumberEmitter(this.number);

  final int number;

  @override
  Future<RequestOrResponse> handle(Request req) async {
    return Response(200, null, "$number")..contentType = ContentType.text;
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

class OKController extends Controller {
  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return Response.ok(null);
  }
}
