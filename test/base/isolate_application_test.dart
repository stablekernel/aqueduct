import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';

main() {
  group("Lifecycle", () {
    var app = new Application<TestSink>();

    tearDownAll(() async {
      await app?.stop();
    });

    test("Application starts", () async {
      await app.start(numberOfInstances: 3);
      expect(app.supervisors.length, 3);
    });

    ////////////////////////////////////////////

    test("Application responds to request", () async {
      var response = await http.get("http://localhost:8080/t");
      expect(response.statusCode, 200);
    });

    test("Application properly routes request", () async {
      var tRequest = http.get("http://localhost:8080/t");
      var rRequest = http.get("http://localhost:8080/r");

      var tResponse = await tRequest;
      var rResponse = await rRequest;

      expect(tResponse.body, '"t_ok"');
      expect(rResponse.body, '"r_ok"');
    });

    test("Application handles a bunch of requests", () async {
      var reqs = <Future>[];
      var responses = [];
      for (int i = 0; i < 100; i++) {
        var req = http.get("http://localhost:8080/t");
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
      expect(
          responses.any(
              (http.Response resp) => resp.headers["server"] == "aqueduct/3"),
          true);
    });

    test("Application stops", () async {
      await app.stop();

      try {
        await http.get("http://localhost:8080/t");
      } on SocketException {}

      await app.start(numberOfInstances: 3);

      var resp = await http.get("http://localhost:8080/t");
      expect(resp.statusCode, 200);
    });
  });

  group("Failures", () {
    test(
        "Application start fails and logs appropriate message if request stream doesn't open",
        () async {
      var crashingApp = new Application<CrashSink>();

      try {
        crashingApp.configuration.configurationOptions = {
          "crashIn": "constructor"
        };
        await crashingApp.start();
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("TestException: constructor"));
      }

      try {
        crashingApp.configuration.configurationOptions = {
          "crashIn": "addRoutes"
        };
        await crashingApp.start();
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("TestException: addRoutes"));
      }

      try {
        crashingApp.configuration.configurationOptions = {
          "crashIn": "willOpen"
        };
        await crashingApp.start();
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("TestException: willOpen"));
      }

      crashingApp.configuration.configurationOptions = {"crashIn": "dontCrash"};
      await crashingApp.start();
      var response = await http.get("http://localhost:8080/t");
      expect(response.statusCode, 200);
      await crashingApp.stop();
    });

    test(
        "Application that fails to open because port is bound fails gracefully",
        () async {
      var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8080);
      server.listen((req) {});

      var conflictingApp = new Application<TestSink>();
      conflictingApp.configuration.port = 8080;

      try {
        await conflictingApp.start();
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e, new isInstanceOf<ApplicationStartupException>());
      }

      await server.close(force: true);
      await conflictingApp.stop();
    });
  });
}

class TestException implements Exception {
  final String message;
  TestException(this.message);

  String toString() {
    return "TestException: $message";
  }
}

class CrashSink extends RequestSink {
  CrashSink(Map<String, dynamic> opts) : super(opts) {
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
