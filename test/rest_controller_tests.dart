@TestOn("vm")

import "package:test/test.dart";
import "dart:core";
import 'test_rest_controller.dart';
import "dart:io";
import 'package:http/http.dart' as http;
import '../bin/monadart.dart';

void main() {

  var server;

  setUp(() {
    return HttpServer.bind("0.0.0.0", 4040).then((incomingServer) {
      server = incomingServer;

      Router router = new Router();
      router.addRoute("/a/[:id]").listen(new TestRESTController());

      // router.route("/a").listen(new Split(new Middleware(), (r) => r.request)).listen(new TestRESTController());
      incomingServer.map((req) => new Request(req)).listen(router.listener);
    });
  });

  tearDown(() {
    server.close();
  });

  test("Router Delivers to controller", () {
    http.get("http://localhost:4040/a").then(expectAsync((response) {
      expect(response.statusCode, equals(200));
      expect(response.body, equals("all"));
    }));
    http.get("http://localhost:4040/a/foobar").then(expectAsync((response) {
      expect(response.statusCode, equals(200));
      expect(response.body, equals("id=foobar"));
    }));
  });

  test("Router hands back 500 for bad handler", () {
    http.put("http://localhost:4040/a").then(expectAsync((response) {
      expect(response.statusCode, equals(500));
    }));
  });

  test("Router hands back 501 for missing method", () {
    http.post("http://localhost:4040/a").then(expectAsync((response) {
      expect(response.statusCode, equals(501));
    }));
  });

  test("Bad route is 404", () {
    http.get("http://localhost:4040/b").then(expectAsync((response) {
      expect(response.statusCode, equals(404));
    }));
  });

}
