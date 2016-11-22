import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

main() {
  group("Application lifecycle", () {
    var app = new Application<TestSink>();

    tearDownAll(() async {
      await app?.stop();
    });

    test("Application starts", () async {
      await app.start(runOnMainIsolate: true);
      expect(app.mainIsolateSink, isNotNull);

      expect(app.supervisors.length, 0);
    });

    test("Application responds to request", () async {
      var response = await http.get("http://localhost:8080/t");
      expect(response.statusCode, 200);
    });

    test("Application properly routes request", () async {
      var tResponse = await http.get("http://localhost:8080/t");
      var rResponse = await http.get("http://localhost:8080/r");

      expect(tResponse.body, '"t_ok"');
      expect(rResponse.body, '"r_ok"');
    });

    test("Application gzips content", () async {
      var resp = await http
          .get("http://localhost:8080/t", headers: {"Accept-Encoding": "gzip"});
      expect(resp.headers["content-encoding"], "gzip");
    });

    test("Application stops", () async {
      await app.stop();

      var successful = false;
      try {
        var _ = await http.get("http://localhost:8080/t");
        successful = true;
      } catch (e) {
        expect(e, isNotNull);
      }
      expect(successful, false);

      await app.start(runOnMainIsolate: true);
      var resp = await http.get("http://localhost:8080/t");
      expect(resp.statusCode, 200);
    });
  });

  group("Failure", () {
    test(
        "Application (on main thread) start fails and logs appropriate message if request stream doesn't open",
        () async {
      var crashingApp = new Application<CrashingTestSink>();

      try {
        crashingApp.configuration.configurationOptions = {
          "crashIn": "constructor"
        };
        await crashingApp.start(runOnMainIsolate: true);
      } catch (e) {
        expect(e.message, "constructor");
      }

      try {
        crashingApp.configuration.configurationOptions = {
          "crashIn": "addRoutes"
        };
        await crashingApp.start(runOnMainIsolate: true);
      } catch (e) {
        expect(e.message, "addRoutes");
      }

      try {
        crashingApp.configuration.configurationOptions = {
          "crashIn": "willOpen"
        };
        await crashingApp.start(runOnMainIsolate: true);
      } catch (e) {
        expect(e.message, "willOpen");
      }

      crashingApp.configuration.configurationOptions = {"crashIn": "dontCrash"};
      await crashingApp.start(runOnMainIsolate: true);
      var response = await http.get("http://localhost:8080/t");
      expect(response.statusCode, 200);
      await crashingApp.stop();
    });

    test("Application can run on main thread", () async {
      var app = new Application<TestSink>();

      await app.start(runOnMainIsolate: true);

      var response = await http.get("http://localhost:8080/t");
      expect(response.statusCode, 200);

      await app.stop();
    });
  });
}

class TestException implements Exception {
  final String message;
  TestException(this.message);
}

class CrashingTestSink extends RequestSink {
  CrashingTestSink(Map<String, dynamic> opts) : super(opts) {
    if (opts["crashIn"] == "constructor") {
      throw new TestException("constructor");
    }
  }

  void setupRouter(Router router) {
    if (options["crashIn"] == "addRoutes") {
      throw new TestException("addRoutes");
    }
    router.route("/t").generate(() => new TController());
  }

  @override
  Future willOpen() async {
    if (options["crashIn"] == "willOpen") {
      throw new TestException("willOpen");
    }
  }
}

class TestSink extends RequestSink {
  TestSink(Map<String, dynamic> opts) : super(opts);

  void setupRouter(Router router) {
    router.route("/t").generate(() => new TController());
    router.route("/r").generate(() => new RController());
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
