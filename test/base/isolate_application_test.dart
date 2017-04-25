import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

main() {
  group("Lifecycle", () {
    Application<TestSink> app;

    setUp(() async {
      app = new Application<TestSink>();
      await app.start(numberOfInstances: 2);
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
      print("send req single");
      var response = await http.get("http://localhost:8081/t");
      print("finished send req single");
      expect(response.statusCode, 200);
    });

    test("Application properly routes request", () async {
      print("sending reqs");
      var tRequest = http.get("http://localhost:8081/t");
      var rRequest = http.get("http://localhost:8081/r");

      var tResponse = await tRequest;
      print("t done");
      var rResponse = await rRequest;
      print("r done");

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

      print("wait for resp");

      await Future.wait(reqs);
      print("resps done");

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
        await http.get("http://localhost:8081/t");
      } on SocketException {}

      await app.start(numberOfInstances: 2);

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

  group("Failures", () {
    test(
        "Application start fails and logs appropriate message if request stream doesn't open",
        () async {
      var crashingApp = new Application<CrashSink>();

      try {
        crashingApp.configuration.options = {"crashIn": "constructor"};
        await crashingApp.start();
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("TestException: constructor"));
      }

      try {
        crashingApp.configuration.options = {"crashIn": "addRoutes"};
        await crashingApp.start();
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("TestException: addRoutes"));
      }

      try {
        crashingApp.configuration.options = {"crashIn": "willOpen"};
        await crashingApp.start();
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("TestException: willOpen"));
      }

      crashingApp.configuration.options = {"crashIn": "dontCrash"};
      await crashingApp.start();
      var response = await http.get("http://localhost:8081/t");
      expect(response.statusCode, 200);
      await crashingApp.stop();
    });

    test(
        "Application that fails to open because port is bound fails gracefully",
        () async {
      var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8081);
      server.listen((req) {});

      var conflictingApp = new Application<TestSink>();
      conflictingApp.configuration.port = 8081;

      try {
        await conflictingApp.start();
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("Failed to create server socket"));
      }

      await server.close(force: true);
    });

    test("Isolate timeout kills application when first isolate fails", () async {
      var timeoutApp = new Application<TimeoutSink>()
        ..isolateStartupTimeout = new Duration(seconds: 1)
        ..configuration.options = {
          "timeout1" : 2
        };

      try {
        await timeoutApp.start(numberOfInstances: 2);
        expect(true, false);
      } on TimeoutException catch (e) {
        expect(e.toString(), contains("Isolate (1) failed to launch"));
      }

      expect(timeoutApp.supervisors.length, 0);
    });

    test("Isolate timeout kills application when first isolate succeeds, but next fails", () async {
      var timeoutApp = new Application<TimeoutSink>()
        ..isolateStartupTimeout = new Duration(seconds: 1)
        ..configuration.options = {
          "timeout2" : 2
        };

      try {
        await timeoutApp.start(numberOfInstances: 2);
        expect(true, false);
      } on TimeoutException catch (e) {
        expect(e.toString(), contains("Isolate (2) failed to launch"));
      }

      expect(timeoutApp.supervisors.length, 0);
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
  CrashSink(ApplicationConfiguration opts) : super(opts) {
    if (opts.options["crashIn"] == "constructor") {
      throw new TestException("constructor");
    }
  }

  void setupRouter(Router router) {
    if (configuration.options["crashIn"] == "addRoutes") {
      throw new TestException("addRoutes");
    }
    router.route("/t").listen((req) async => new Response.ok("t_ok"));
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

  void setupRouter(Router router) {
    router.route("/t").listen((req) async => new Response.ok("t_ok"));
    router.route("/r").listen((req) async => new Response.ok("r_ok"));
    router.route("startup").listen((r) async {
      var total = configuration.options["startup"].fold(0, (a, b) => a + b);
      return new Response.ok("$total");
    });
  }
}

class TimeoutSink extends RequestSink {
  TimeoutSink(ApplicationConfiguration config) : super(config);
  void setupRouter(Router router) {}

  @override
  Future willOpen() async {
    var timeoutLength = configuration.options["timeout${server.identifier}"];
    if (timeoutLength == null) {
      return;
    }

    await new Future.delayed(new Duration(seconds: timeoutLength));
  }
}
