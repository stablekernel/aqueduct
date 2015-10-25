import 'package:test/test.dart';
import '../lib/monadart.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

main() {
  var app = new Application();
  app.configuration.port = 8080;
  app.pipelineType = TPipeline;

  test("Application starts", () async {

    await app.start(numberOfInstances: 3);
    expect(app.servers.length, 3);
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

    var reqs = [];
    var responses = [];
    for(int i = 0; i < 100; i++) {
      var req = http.get("http://localhost:8080/t");
      req.then((resp) {
        responses.add(resp);
      });
      reqs.add(req);
    }

    await Future.wait(reqs);

    expect(responses.any((http.Response resp) => resp.headers["server"] == "monadart/1"), true);
    expect(responses.any((http.Response resp) => resp.headers["server"] == "monadart/2"), true);
    expect(responses.any((http.Response resp) => resp.headers["server"] == "monadart/3"), true);

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
