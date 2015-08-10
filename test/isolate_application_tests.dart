import 'package:test/test.dart';
import '../lib/monadart.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';

main() {
  var app = new Application();
  app.instanceCount = 3;
  app.port = 8080;
  app.addControllerForPath(TController, "t");
  app.addControllerForPath(RController, "r");

  test("Application starts", () async {
    await app.start();
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

class TController extends ResourceController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("t_ok");
  }
}

class RController extends ResourceController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("r_ok");
  }
}
