@TestOn("vm")

import "package:test/test.dart";
import "dart:core";
import '../bin/Router.dart';
import "dart:io";
import 'package:http/http.dart' as http;

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
    return HttpServer.bind("0.0.0.0", 4040).then((incomingServer) {
      Router router = new Router();
      router.route("/player").listen(basicHandler);
      router.route("/text").listen(textHandler);
      router.route("/a/:id").listen(echoHandler);
      incomingServer.listen(router.listener);
      server = incomingServer;
    });
  });

  tearDown(() {
    server.close();
  });

  test("Router Actually Handles Requests", () {
    http.get("http://localhost:4040/player").then(expectAsync((response) {
      expect(response.statusCode, equals(200));
    }));
    http.get("http://localhost:4040/notplayer").then(expectAsync((response) {
      expect(response.statusCode, equals(404));
    }));
    http.get("http://localhost:4040/text").then(expectAsync((response) {
      expect(response.statusCode, equals(200));
      expect(response.body, equals("text"));
    }));
  });

  test("Router delivers values", () {
    http.get("http://localhost:4040/a/foobar").then(expectAsync((response) {
      expect(response.statusCode, equals(200));
      expect(response.body, equals("foobar"));
    }));
  });
}

void echoHandler(RoutedHttpRequest req) {
  req.request.response.statusCode = 200;
  req.request.response.write(req.pathValues["id"]);
  req.request.response.close();
}

void basicHandler(RoutedHttpRequest req) {
  req.request.response.statusCode = 200;
  req.request.response.close();
}

void textHandler(RoutedHttpRequest req) {
  req.request.response.statusCode = 200;
  req.request.response.write("text");
  req.request.response.close();
}