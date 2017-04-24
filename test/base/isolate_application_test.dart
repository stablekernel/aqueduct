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
    });

    tearDown(() async {
      await app?.stop();
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
        expect(e, new isInstanceOf<ApplicationStartupException>());
      }

      await server.close(force: true);
    });
  });

  group("SSL", () {
    Application app;

    tearDown(() async {
      await app?.stop();
    });

    test("Start with HTTPS", () async {
      var ciDirUri = new Directory("ci").uri;

      app = new Application<TestSink>()
        ..configuration.certificateFilePath = ciDirUri.resolve("aqueduct.cert.pem").path
        ..configuration.privateKeyFilePath = ciDirUri.resolve("aqueduct.key.pem").path;

      await app.start(numberOfInstances: 1);

      var completer = new Completer();
      var socket = await SecureSocket.connect("localhost", 8081, onBadCertificate: (_) => true);
      var request = "GET /r HTTP/1.1\r\nConnection: close\r\nHost: localhost\r\n\r\n";
      socket.add(request.codeUnits);

      socket.listen((bytes) => completer.complete(bytes));
      var httpResult = new String.fromCharCodes(await completer.future);
      expect(httpResult, contains("200 OK"));
      expect(httpResult, contains("r_ok"));
      await socket.close();
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
