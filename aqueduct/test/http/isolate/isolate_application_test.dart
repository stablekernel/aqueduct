// ignore: unnecessary_const
@Timeout(const Duration(seconds: 120))
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group("Lifecycle", () {
    Application<TestChannel> app;

    setUp(() async {
      app = Application<TestChannel>();
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
      var response = await http.get("http://localhost:8888/t");
      expect(response.statusCode, 200);
    });

    test("Application properly routes request", () async {
      var tRequest = http.get("http://localhost:8888/t");
      var rRequest = http.get("http://localhost:8888/r");

      var tResponse = await tRequest;
      var rResponse = await rRequest;

      expect(tResponse.body, '"t_ok"');
      expect(rResponse.body, '"r_ok"');
    });

    test("Application handles a bunch of requests", () async {
      var reqs = <Future>[];
      var responses = <http.Response>[];
      for (int i = 0; i < 20; i++) {
        var req = http.get("http://localhost:8888/t");
        // ignore: unawaited_futures
        req.then((resp) {
          responses.add(resp);
        });
        reqs.add(req);
      }

      await Future.wait(reqs);

      expect(
          responses.any(
              (http.Response resp) => resp.headers["server"] == "aqueduct/1"),
          true);
      expect(
          responses.any(
              (http.Response resp) => resp.headers["server"] == "aqueduct/2"),
          true);
    });

    test("Application stops", () async {
      await app.stop();

      try {
        await http.get("http://localhost:8888/t");
        // ignore: empty_catches
      } on SocketException {}

      await app.start(numberOfInstances: 2, consoleLogging: true);

      var resp = await http.get("http://localhost:8888/t");
      expect(resp.statusCode, 200);
    });

    test(
        "Application runs app startup function once, regardless of isolate count",
        () async {
      var sum = 0;
      for (var i = 0; i < 10; i++) {
        var result = await http.get("http://localhost:8888/startup");
        sum += int.parse(json.decode(result.body) as String);
      }
      expect(sum, 10);
    });
  });

  group("App launch status", () {
    Application<TestChannel> app;

    tearDown(() async {
      await app?.stop();
    });

    test(
        "didFinishLaunching is false before launch, true after, false after stop",
        () async {
      app = Application<TestChannel>();
      expect(app.isRunning, false);

      var future = app.start(numberOfInstances: 2, consoleLogging: true);
      expect(app.isRunning, false);
      await future;
      expect(app.isRunning, true);

      await app.stop();
      expect(app.isRunning, false);
    });
  });
}

class TestChannel extends ApplicationChannel {
  static Future initializeApplication(ApplicationOptions config) async {
    final v = config.context["startup"] as List<int> ?? [];
    v.add(1);
    config.context["startup"] = v;
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/t").linkFunction((req) async => Response.ok("t_ok"));
    router.route("/r").linkFunction((req) async => Response.ok("r_ok"));
    router.route("startup").linkFunction((r) async {
      var total = options.context["startup"].fold(0, (a, b) => a + b);
      return Response.ok("$total");
    });
    return router;
  }
}
