import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:isolate';
import 'dart:io';
import 'dart:async';

void main() {
  group("Mock HTTP Tests", () {
    MockHTTPServer server = new MockHTTPServer(4000);
    var testClient = new TestClient(4000);

    test("Server opens", () async {
      var openFuture = server.open();
      expect(openFuture, completes);
    });

    test("Request is enqueued and immediately available", () async {
      var response = (testClient.request("/hello?foo=bar")..headers = {
        "X" : "Y"
      }).get();
      expect(response, completes);

      var serverRequest = await server.next();
      expect(serverRequest.method, "GET");
      expect(serverRequest.path, "/hello");
      expect(serverRequest.queryParameters["foo"], "bar");
      expect(serverRequest.headers["x"], "Y");
    });

    test("Request body is captured", () async {
      var req = testClient.request("/foo")..json = {
        "a" : "b"
      };
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

    test("Delayed queued responses show up later", () async {
      server.queueResponse(new Response.ok(null), delay: 5);
      var time = new DateTime.now();
      var response = await testClient.request("/foo").get();
      var nowTime = new DateTime.now();
      var diff = time.difference(nowTime).inSeconds.abs();
      expect(diff, greaterThanOrEqualTo(5));
    });

  });
}

Future spawnFunc(List pair) async {
  var path = pair.first;
  var delay = pair.last;
  var testClient = new TestClient(4000);
  sleep(new Duration(seconds: delay));
  await testClient.request(path).get();
}