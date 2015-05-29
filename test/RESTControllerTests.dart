@TestOn("vm")

import "package:test/test.dart";
import "dart:core";
import 'TestRESTController.dart';
import "dart:io";
import 'package:http/http.dart' as http;
import '../bin/monadart.dart';

void main() {

  var server;

  setUp(() {
    return HttpServer.bind("0.0.0.0", 4040).then((incomingServer) {
      server = incomingServer;

      Router router = new Router();
      router.route("/a/[:id]").listen(new TestRESTController());

      incomingServer.listen(router.listener);
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

}
