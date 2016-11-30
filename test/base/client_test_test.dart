import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'dart:async';

main() {
  test("Client can expect array of JSON", () async {
    TestClient client = new TestClient.onPort(8080);
    HttpServer server =
        await HttpServer.bind("localhost", 8080, v6Only: false, shared: false);
    var router = new Router();
    router.route("/na").generate(() => new TestController());
    router.finalize();
    server.map((req) => new Request(req)).listen(router.receive);

    var resp = await client.request("/na").get();
    expect(resp, hasResponse(200, everyElement({"id": greaterThan(0)})));

    await server?.close(force: true);
  });
}

class TestController extends HTTPController {
  @httpGet
  get() async {
    return new Response.ok([
      {"id": 1},
      {"id": 2}
    ]);
  }
}
