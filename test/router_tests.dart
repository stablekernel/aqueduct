@TestOn("vm")

import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'package:http/http.dart' as http;
import '../lib/monadart.dart';

//const int workers = 4;
//
//worker(int id) async {
//  var server = await HttpServer.bind("0.0.0.0", 8080, shared: true);
//
//  await for (var request in server) {
//    request.response
//      ..writeln("Worker ${id} says hello!")
//      ..close();
//  }
//}
//
//main() async {
//  for (var i = 1; i <= workers; i++) {
//    var isolate = await Isolate.spawn(worker, i);
//    print("Worker #${i} spawned.");
//  }
//}

void main() {

  var server;

  setUp(() {
    return HttpServer.bind(InternetAddress.ANY_IP_V4, 4040).then((incomingServer) {
      server = incomingServer;

      Router router = new Router();

      router.addRoute("/player").listen(basicHandler);
      router.addRoute("/text").listen(textHandler);
      router.addRoute("/a/:id").listen(echoHandler);
      router.addRoute("/raw").map((r) => r.request).listen(rawHandler);

      incomingServer.map((req) => new ResourceRequest((req))).listen(router.listener);
    });
  });

  tearDown(() {
    server.close();
  });

  test("Router Actually Handles Requests", () async {
    var response = await http.get("http://localhost:4040/player");
    expect(response.statusCode, equals(200));

    response = await http.get("http://localhost:4040/notplayer");
    expect(response.statusCode, equals(404));

    response = await http.get("http://localhost:4040/text");
    expect(response.statusCode, equals(200));
    expect(response.body, equals("text"));
  });

  test("Router delivers values", () async {
    var response = await http.get("http://localhost:4040/a/foobar");
    expect(response.statusCode, equals(200));
    expect(response.body, equals("foobar"));
  });

  test("Downgrade", () async {
    var response = await http.get("http://localhost:4040/raw");
    expect(response.statusCode, equals(200));
  });
}

void echoHandler(ResourceRequest req) {
  req.request.response.statusCode = 200;
  req.request.response.write(req.pathParameters["id"]);
  req.request.response.close();
}

void basicHandler(ResourceRequest req) {
  req.request.response.statusCode = 200;
  req.request.response.close();
}

void textHandler(ResourceRequest req) {
  req.request.response.statusCode = 200;
  req.request.response.write("text");
  req.request.response.close();
}

void rawHandler(HttpRequest req) {
  req.response.statusCode = 200;
  req.response.close();
}