import 'dart:async';
import 'dart:convert';

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
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

      await app.startOnCurrentIsolate();
      expect(app.isRunning, true);

      await app.stop();
      expect(app.isRunning, false);
    });
  });

  group("Application lifecycle", () {
    Application<TestChannel> app;

    setUp(() async {
      app = Application<TestChannel>();
      await app.startOnCurrentIsolate();
    });

    tearDown(() async {
      await app?.stop();
    });

    test("Application starts", () async {
      expect(app.channel, isNotNull);
      expect(app.supervisors.length, 0);
    });

    test("Application responds to request", () async {
      var response = await http.get("http://localhost:8888/t");
      expect(response.statusCode, 200);
    });

    test("Application properly routes request", () async {
      var tResponse = await http.get("http://localhost:8888/t");
      var rResponse = await http.get("http://localhost:8888/r");

      expect(tResponse.body, '"t_ok"');
      expect(rResponse.body, '"r_ok"');
    });

    test("Application gzips content", () async {
      var resp = await http
          .get("http://localhost:8888/t", headers: {"Accept-Encoding": "gzip"});
      expect(resp.headers["content-encoding"], "gzip");
    });

    test("Application stops", () async {
      await app.stop();

      var successful = false;
      try {
        var _ = await http.get("http://localhost:8888/t");
        successful = true;
      } catch (e) {
        expect(e, isNotNull);
      }
      expect(successful, false);

      await app.startOnCurrentIsolate();
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

  group("Failure", () {
    test(
        "Application (on main thread) start fails and logs appropriate message if request stream doesn't open",
        () async {
      var crashingApp = Application<CrashingTestChannel>();

      try {
        crashingApp.options.context = {"crashIn": "addRoutes"};
        await crashingApp.startOnCurrentIsolate();
        expect(true, false);
      } on Exception catch (e) {
        expect(e.toString(), contains("addRoutes"));
      }

      try {
        crashingApp.options.context = {"crashIn": "prepare"};
        await crashingApp.startOnCurrentIsolate();
        expect(true, false);
      } on Exception catch (e) {
        expect(e.toString(), contains("prepare"));
      }

      crashingApp.options.context = {"crashIn": "dontCrash"};
      await crashingApp.startOnCurrentIsolate();
      var response = await http.get("http://localhost:8888/t");
      expect(response.statusCode, 200);
      await crashingApp.stop();
    });
  });
}

class TestException implements Exception {
  TestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CrashingTestChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = Router();
    if (options.context["crashIn"] == "addRoutes") {
      throw TestException("addRoutes");
    }
    router.route("/t").link(() => TController());
    return router;
  }

  @override
  Future prepare() async {
    if (options.context["crashIn"] == "prepare") {
      throw TestException("prepare");
    }
  }
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
    router.route("/t").link(() => TController());
    router.route("/r").link(() => RController());
    router.route("startup").linkFunction((r) async {
      var total = options.context["startup"].fold(0, (a, b) => a + b);
      return Response.ok("$total");
    });
    return router;
  }
}

class TController extends Controller {
  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return Response.ok("t_ok");
  }
}

class RController extends Controller {
  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return Response.ok("r_ok");
  }
}
