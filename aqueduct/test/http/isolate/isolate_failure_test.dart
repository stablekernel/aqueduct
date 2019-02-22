import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  tearDownAll(Logger("aqueduct").clearListeners);

  group("Failures", () {
    test(
        "Application start fails and logs appropriate message if request stream doesn't open",
        () async {
      var crashingApp = Application<CrashChannel>();

      try {
        crashingApp.options.context = {"crashIn": "addRoutes"};
        await crashingApp.start(consoleLogging: true);
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("TestException: addRoutes"));
      }

      try {
        crashingApp.options.context = {"crashIn": "prepare"};
        await crashingApp.start(consoleLogging: true);
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("TestException: prepare"));
      }

      crashingApp.options.context = {"crashIn": "dontCrash"};
      await crashingApp.start(consoleLogging: true);
      var response = await http.get("http://localhost:8888/t");
      expect(response.statusCode, 200);
      await crashingApp.stop();
    });

    test(
        "Application that fails to open because port is bound fails gracefully",
        () async {
      var server = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
      server.listen((req) {});

      var conflictingApp = Application<TestChannel>();
      conflictingApp.options.port = 8888;

      try {
        await conflictingApp.start(consoleLogging: true);
        expect(true, false);
      } on ApplicationStartupException catch (e) {
        expect(e.toString(), contains("Failed to create server socket"));
      }

      await server.close(force: true);
    });

    test("Isolate timeout kills application when first isolate fails",
        () async {
      var timeoutApp = Application<TimeoutChannel>()
        ..isolateStartupTimeout = const Duration(seconds: 4)
        ..options.context = {"timeout1": 10};

      try {
        await timeoutApp.start(numberOfInstances: 2, consoleLogging: true);
        expect(true, false);
      } on TimeoutException catch (e) {
        expect(e.toString(), contains("Isolate (1) failed to launch"));
      }

      expect(timeoutApp.supervisors.length, 0);
      print("-- test completes");
    });

    test(
        "Isolate timeout kills application when first isolate succeeds, but next fails",
        () async {
      var timeoutApp = Application<TimeoutChannel>()
        ..isolateStartupTimeout = const Duration(seconds: 4)
        ..options.context = {"timeout2": 10};

      try {
        await timeoutApp.start(numberOfInstances: 2, consoleLogging: true);
        expect(true, false);
      } on TimeoutException catch (e) {
        expect(e.toString(), contains("Isolate (2) failed to launch"));
      }

      expect(timeoutApp.supervisors.length, 0);
      print("-- test completes");
    });
  });
}

class TimeoutChannel extends ApplicationChannel {
  Timer timer;

  @override
  Controller get entryPoint {
    return Router();
  }

  @override
  Future prepare() async {
    final timeoutLength = options.context["timeout${server.identifier}"] as int;
    if (timeoutLength == null) {
      return;
    }

    var completer = Completer();
    var elapsed = 0;
    timer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      elapsed += 500;
      print("waiting...");
      if (elapsed > timeoutLength * 1000) {
        completer.complete();
        t.cancel();
      }
    });
    await completer.future;
  }

  @override
  Future close() async {
    timer?.cancel();
    await super.close();
  }
}

class TestException implements Exception {
  TestException(this.message);

  final String message;

  @override
  String toString() {
    return "TestException: $message";
  }
}

class CrashChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = Router();
    if (options.context["crashIn"] == "addRoutes") {
      throw TestException("addRoutes");
    }
    router.route("/t").linkFunction((req) async => Response.ok("t_ok"));
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
    router.route("/t").linkFunction((req) async => Response.ok("t_ok"));
    router.route("/r").linkFunction((req) async => Response.ok("r_ok"));
    router.route("startup").linkFunction((r) async {
      var total = options.context["startup"].fold(0, (a, b) => a + b);
      return Response.ok("$total");
    });
    return router;
  }
}
