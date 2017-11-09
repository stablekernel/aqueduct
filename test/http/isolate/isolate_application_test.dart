import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import '../../helpers.dart';

void main() {
  setUpAll(() {
    justLogEverything();
  });

  group("Lifecycle", () {
    Application<TestChannel> app;

    setUp(() async {
      app = new Application<TestChannel>();
      await app.start(numberOfInstances: 2, consoleLogging: true);
      print("started");
    });

    tearDown(() async {
      print("stopping");
      await app?.stop();
      print("stopped");
    });

    test("Application starts", () async {
      expect(app.supervisors.length, 2);
    });

    test("Application responds to request", () async {
      var response = await http.get("http://localhost:8081/t");
      expect(response.statusCode, 200);
    });

    test("Application properly routes request", () async {
      var tRequest = http.get("http://localhost:8081/t");
      var rRequest = http.get("http://localhost:8081/r");

      var tResponse = await tRequest;
      var rResponse = await rRequest;

      expect(tResponse.body, '"t_ok"');
      expect(rResponse.body, '"r_ok"');
    });

    test("Application handles a bunch of requests", () async {
      var reqs = <Future>[];
      var responses = [];
      for (int i = 0; i < 20; i++) {
        var req = http.get("http://localhost:8081/t");
        req.then((resp) {
          responses.add(resp);
        });
        reqs.add(req);
      }

      await Future.wait(reqs);

      expect(responses.any((http.Response resp) => resp.headers["server"] == "aqueduct/1"), true);
      expect(responses.any((http.Response resp) => resp.headers["server"] == "aqueduct/2"), true);
    });

    test("Application stops", () async {
      await app.stop();

      try {
        await http.get("http://localhost:8081/t");
      } on SocketException {}

      await app.start(numberOfInstances: 2, consoleLogging: true);

      var resp = await http.get("http://localhost:8081/t");
      expect(resp.statusCode, 200);
    });

    test("Application runs app startup function once, regardless of isolate count", () async {
      var sum = 0;
      for (var i = 0; i < 10; i++) {
        var result = await http.get("http://localhost:8081/startup");
        sum += int.parse(JSON.decode(result.body));
      }
      expect(sum, 10);
    });
  });

  group("App launch status", () {
    Application<TestChannel> app;

    tearDown(() async {
      await app?.stop();
    });

    test("didFinishLaunching is false before launch, true after, false after stop", () async {
      app = new Application<TestChannel>();
      expect(app.hasFinishedLaunching, false);

      var future = app.start(numberOfInstances: 2, consoleLogging: true);
      expect(app.hasFinishedLaunching, false);
      await future;
      expect(app.hasFinishedLaunching, true);

      await app.stop();
      expect(app.hasFinishedLaunching, false);
    });
  });
}

class TestChannel extends ApplicationChannel {
  static Future initializeApplication(ApplicationOptions config) async {
    List<int> v = config.context["startup"] ?? [];
    v.add(1);
    config.context["startup"] = v;
  }

  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/t").listen((req) async => new Response.ok("t_ok"));
    router.route("/r").listen((req) async => new Response.ok("r_ok"));
    router.route("startup").listen((r) async {
      var total = options.context["startup"].fold(0, (a, b) => a + b);
      return new Response.ok("$total");
    });
    return router;
  }
}
