import 'package:test/test.dart';
import '../lib/monadart.dart';
import 'dart:async';
import 'package:http/http.dart' as http;


Future main() async {
  var app = new Application();
  app.pipelineType = Pipeline;
  app.configuration.port = 8080;

  await app.start();

  test("Something", () async {
    var response = await http.get("http://localhost:8080/a");
    print("${response.body}");
  });
}

class Pipeline extends ApplicationPipeline {
  var router = new Router();

  @override
  RequestHandler initialHandler() {
    return router;
  }

  @override
  void willOpen() {
    router.route("/a").then(new Adapter("a").then(new Adapter("b").then(new RequestHandlerGenerator<EndController>())));
  }

}

class Adapter extends RequestHandler {
  String key;

  Adapter(this.key);

  @override
  Future<RequestHandlerResult> processRequest(ResourceRequest req) async {
    req.context[key] = "true";
    return req;
  }
}

class EndController extends HttpController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok(resourceRequest.context);
  }
}