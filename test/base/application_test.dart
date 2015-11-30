import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

main() {
  var app = new Application<TPipeline>();
  app.configuration.port = 8080;

  tearDownAll(() async {
    app.stop();
  });

  test("Application starts", () async {
    await app.start();
    expect(app.servers.length, 1);
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
  });
}

class TPipeline extends ApplicationPipeline {
  Router router;

  @override
  RequestHandler initialHandler() {
    return router;
  }

  @override
  Future willOpen() async {
    router = new Router();

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