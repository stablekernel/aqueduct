import 'dart:async';
import 'dart:io';

import 'package:aqueduct/test.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  test("Client can expect array of JSON", () async {
    TestClient client = new TestClient.onPort(8888);
    HttpServer server =
        await HttpServer.bind("localhost", 8888, v6Only: false, shared: false);
    var router = new Router();
    router.route("/na").link(() => new TestController());
    router.prepare();
    server.map((req) => new Request(req)).listen(router.receive);

    var resp = await client.request("/na").get();
    expect(resp, hasResponse(200, everyElement({"id": greaterThan(0)})));

    await server?.close(force: true);
  });
}

class TestController extends RESTController {
  @Operation.get()
  Future<Response> get() async {
    return new Response.ok([
      {"id": 1},
      {"id": 2}
    ]);
  }
}
