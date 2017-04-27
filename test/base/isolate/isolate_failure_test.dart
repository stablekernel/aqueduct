import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';

main() {
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

    //todo: disabling tests. apparently issue with isolates on linux
//    test("Isolate timeout kills application when first isolate fails", () async {
//      var timeoutApp = new Application<TimeoutSink>()
//        ..isolateStartupTimeout = new Duration(seconds: 4)
//        ..configuration.options = {
//          "timeout1" : 2
//        };
//
//      try {
//        await timeoutApp.start(numberOfInstances: 2);
//        expect(true, false);
//      } on TimeoutException catch (e) {
//        expect(e.toString(), contains("Isolate (1) failed to launch"));
//      }
//
//      expect(timeoutApp.supervisors.length, 0);
//    });
//
//    test("Isolate timeout kills application when first isolate succeeds, but next fails", () async {
//      var timeoutApp = new Application<TimeoutSink>()
//        ..isolateStartupTimeout = new Duration(seconds: 4)
//        ..configuration.options = {
//          "timeout2" : 2
//        };
//
//      try {
//        await timeoutApp.start(numberOfInstances: 2);
//        expect(true, false);
//      } on TimeoutException catch (e) {
//        expect(e.toString(), contains("Isolate (2) failed to launch"));
//      }
//
//      expect(timeoutApp.supervisors.length, 0);
//    });
  });
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