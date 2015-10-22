import 'package:test/test.dart';
import '../lib/monadart.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

main() {
  var app = new Application();
  app.configuration.port = 8080;
  app.pipelineType = TPipeline;

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
}

class TPipeline extends ApplicationPipeline {
  Router router;

  @override
  RequestHandler initialHandler() {
    return router;
  }

  @override
  void willOpen() {
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