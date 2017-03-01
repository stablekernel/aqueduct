import 'dart:io';
import 'dart:async';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:aqueduct/test.dart';

void main() {
  group("Mock HTTP Tests", () {
    MockHTTPServer server = new MockHTTPServer(4000);
    var testClient = new TestClient.onPort(4000);

    test("Server opens", () async {
      var openFuture = server.open();
      expect(openFuture, completes);
    });

    tearDownAll(() async {
      await server.close();
    });

    test("Request is enqueued and immediately available", () async {
      var response =
          (testClient.request("/hello?foo=bar")..headers = {"X": "Y"}).get();
      expect(response, completes);

      var serverRequest = await server.next();
      expect(serverRequest.method, "GET");
      expect(serverRequest.path, "/hello");
      expect(serverRequest.queryParameters["foo"], "bar");
      expect(serverRequest.headers["x"], "Y");
    });

    test("Request body is captured", () async {
      var req = testClient.request("/foo")..json = {"a": "b"};
      await req.put();

      var serverRequest = await server.next();
      expect(serverRequest.method, "PUT");
      expect(serverRequest.body, '{"a":"b"}');
      expect(serverRequest.jsonBody["a"], "b");
    });

    test("Wait for request that will happen in future", () async {
      Isolate.spawn(spawnFunc, ["/foo", 1]);
      Isolate.spawn(spawnFunc, ["/bar", 2]);

      var serverRequest = await server.next();
      expect(serverRequest.path, "/foo");
      serverRequest = await server.next();
      expect(serverRequest.path, "/bar");
    });
  });
}

Future spawnFunc(List pair) async {
  var path = pair.first;
  var delay = pair.last;
  var testClient = new TestClient.onPort(4000);
  sleep(new Duration(seconds: delay));
  await testClient.request(path).get();
}
