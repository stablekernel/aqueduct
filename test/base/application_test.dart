import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  group("Application lifecycle", () {
    Application<TestSink> app;

    setUp(() async {
      app = new Application<TestSink>();
      await app.start(runOnMainIsolate: true);
    });

    tearDown(() async {
      await app?.stop();
    });

    test("Application starts", () async {
      expect(app.mainIsolateSink, isNotNull);
      expect(app.supervisors.length, 0);
    });

    test("Application responds to request", () async {
      var response = await http.get("http://localhost:8081/t");
      expect(response.statusCode, 200);
    });

    test("Application properly routes request", () async {
      var tResponse = await http.get("http://localhost:8081/t");
      var rResponse = await http.get("http://localhost:8081/r");

      expect(tResponse.body, '"t_ok"');
      expect(rResponse.body, '"r_ok"');
    });

    test("Application gzips content", () async {
      var resp = await http
          .get("http://localhost:8081/t", headers: {"Accept-Encoding": "gzip"});
      expect(resp.headers["content-encoding"], "gzip");
    });

    test("Application stops", () async {
      await app.stop();

      var successful = false;
      try {
        var _ = await http.get("http://localhost:8081/t");
        successful = true;
      } catch (e) {
        expect(e, isNotNull);
      }
      expect(successful, false);

      await app.start(runOnMainIsolate: true);
      var resp = await http.get("http://localhost:8081/t");
      expect(resp.statusCode, 200);
    });

    test(
        "Application runs app startup function once, regardless of isolate count",
        () async {
      var sum = 0;
      for (var i = 0; i < 10; i++) {
        var result = await http.get("http://localhost:8081/startup");
        sum += int.parse(JSON.decode(result.body));
      }
      expect(sum, 10);
    });
  });

  group("Failure", () {
    test(
        "Application (on main thread) start fails and logs appropriate message if request stream doesn't open",
        () async {
      var crashingApp = new Application<CrashingTestSink>();

      try {
        crashingApp.configuration.options = {"crashIn": "constructor"};
        await crashingApp.start(runOnMainIsolate: true);
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.originalException.toString(), contains("constructor"));
      }

      try {
        crashingApp.configuration.options = {"crashIn": "addRoutes"};
        await crashingApp.start(runOnMainIsolate: true);
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.originalException.toString(), contains("addRoutes"));
      }

      try {
        crashingApp.configuration.options = {"crashIn": "willOpen"};
        await crashingApp.start(runOnMainIsolate: true);
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.originalException.toString(), contains("willOpen"));
      }

      crashingApp.configuration.options = {"crashIn": "dontCrash"};
      await crashingApp.start(runOnMainIsolate: true);
      var response = await http.get("http://localhost:8081/t");
      expect(response.statusCode, 200);
      await crashingApp.stop();
    });
  });
}

class TestException implements Exception {
  final String message;
  TestException(this.message);

  @override
  String toString() => message;
}

class CrashingTestSink extends RequestSink {
  CrashingTestSink(ApplicationConfiguration opts) : super(opts) {
    if (opts.options["crashIn"] == "constructor") {
      throw new TestException("constructor");
    }
  }

  @override
  void setupRouter(Router router) {
    if (configuration.options["crashIn"] == "addRoutes") {
      throw new TestException("addRoutes");
    }
    router.route("/t").generate(() => new TController());
  }

  @override
  Future willOpen() async {
    if (configuration.options["crashIn"] == "willOpen") {
      throw new TestException("willOpen");
    }
  }
}

class TestSink extends RequestSink {
  static Future initializeApplication(ApplicationConfiguration config) async {
    List<int> v = config.options["startup"] ?? [];
    v.add(1);
    config.options["startup"] = v;
  }

  TestSink(ApplicationConfiguration opts) : super(opts);

  @override
  void setupRouter(Router router) {
    router.route("/t").generate(() => new TController());
    router.route("/r").generate(() => new RController());
    router.route("startup").listen((r) async {
      var total = configuration.options["startup"].fold(0, (a, b) => a + b);
      return new Response.ok("$total");
    });
  }
}

class TController extends HTTPController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("t_ok");
  }
}

class RController extends HTTPController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("r_ok");
  }
}
