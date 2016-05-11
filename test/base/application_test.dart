import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

main() {
  var app = new Application<TPipeline>();
  app.configuration.port = 8080;

  tearDownAll(() async {
    await app.stop();
  });

  group("Application lifecycle", () {
    test("Application starts", () async {
      await app.start();
      expect(app.supervisors.length, 1);
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
      var resp = await http.get("http://localhost:8080/t");
      expect(resp.headers["content-encoding"], "gzip");
    });

    test("Application stops", () async {
      await app.stop();

      try {
        var _ = await http.get("http://localhost:8080/t");
        fail("This should fail immeidlatey");
      } catch (e) {
        expect(e, isNotNull);
      }

      await app.start();
      var resp = await http.get("http://localhost:8080/t");
      expect(resp.statusCode, 200);

      await app.stop();
    });
  });

  test("Application (on main thread) start fails and logs appropriate message if pipeline doesn't open", () async {
    var crashingApp = new Application<CrashPipeline>();

    try {
      crashingApp.configuration.pipelineOptions = {"crashIn" : "constructor"};
      await crashingApp.start(runOnMainIsolate: true);
    } catch (e) {
      expect(e.message, "constructor");
    }

    try {
      crashingApp.configuration.pipelineOptions = {"crashIn" : "addRoutes"};
      await crashingApp.start(runOnMainIsolate: true);
    } catch (e) {
      expect(e.message, "addRoutes");
    }

    try {
      crashingApp.configuration.pipelineOptions = {"crashIn" : "willOpen"};
      await crashingApp.start(runOnMainIsolate: true);
    } catch (e) {
      expect(e.message, "willOpen");
    }

    crashingApp.configuration.pipelineOptions = {"crashIn" : "dontCrash"};
    await crashingApp.start(runOnMainIsolate: true);
    var response = await http.get("http://localhost:8080/t");
    expect(response.statusCode, 200);
    await crashingApp.stop();
  });

  test("Application can run on main thread", () async {
    await app.start(runOnMainIsolate: true);

    var response = await http.get("http://localhost:8080/t");
    expect(response.statusCode, 200);

    await app.stop();
  });
}

class TestException implements Exception {
  final String message;
  TestException(this.message);
}

class CrashPipeline extends ApplicationPipeline {
  CrashPipeline(Map opts) : super(opts) {
    if (opts["crashIn"] == "constructor") {
      throw new TestException("constructor");
    }
  }

  void addRoutes() {
    if (options["crashIn"] == "addRoutes") {
      throw new TestException("addRoutes");
    }
    router.route("/t").then(new RequestHandlerGenerator<TController>());
  }

  @override
  Future willOpen() async {
    if (options["crashIn"] == "willOpen") {
      throw new TestException("willOpen");
    }
  }
}

class TPipeline extends ApplicationPipeline {
  TPipeline(Map opts) : super(opts);

  void addRoutes() {
    router.route("/t").then(new RequestHandlerGenerator<TController>());
    router.route("/r").then(new RequestHandlerGenerator<RController>());

  }
}

class TController extends HttpController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("t_ok");
  }
}

class RController extends HttpController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("r_ok");
  }
}