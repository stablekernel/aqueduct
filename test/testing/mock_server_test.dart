import 'dart:io';
import 'dart:async';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:aqueduct/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  group("Mock HTTP Tests", () {
    MockHTTPServer server = new MockHTTPServer(4000);
    var testClient = new TestClient.onPort(4000);

    test("Server opens", () async {
      final openFuture = server.open();
      expect(openFuture, completes);
    });

    tearDownAll(() async {
      await server.close();
    });

    test("Request is enqueued and immediately available", () async {
      final response =
          (testClient.request("/hello?foo=bar")..headers = {"X": "Y"}).get();
      expect(response, completes);

      final serverRequest = await server.next();
      expect(serverRequest.method, "GET");
      expect(serverRequest.path, "/hello");
      expect(serverRequest.queryParameters["foo"], "bar");
      expect(serverRequest.headers["x"], "Y");
    });

    test("Request body is captured", () async {
      final req = testClient.request("/foo")..json = {"a": "b"};
      await req.put();

      final serverRequest = await server.next();
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

    test("Clear and empty", () async {
      await (testClient.request("/hello?foo=bar")..headers = {"X": "Y"}).get();
      expect(server.isEmpty, false);
      server.clear();
      expect(server.isEmpty, true);
    });

    test("Mock server returns an error by default if there are no enqueued requests", () async {
      final response = await testClient.request("/hello").get();
      expect(response.statusCode, 503);
    });

    test("Mock server default response can be changed", () async {
      server.defaultResponse = new Response.ok({"key": "This is the default response"});

      final response = await testClient.request("/hello").get();
      expect(response, hasResponse(200, {"key": "This is the default response"}));
    });

    test("Queued response count returns correct number of queued requests", () async {
      expect(server.queuedResponseCount, 0);
      server.queueResponse(new Response.ok(null));
      expect(server.queuedResponseCount, 1);
      server.queueResponse(new Response.unauthorized());
      expect(server.queuedResponseCount, 2);
      await testClient.request("/hello").get();
      expect(server.queuedResponseCount, 1);
      await testClient.request("/hello").post();
      expect(server.queuedResponseCount, 0);
      await testClient.request("/hello").get(); // Returns default response
      expect(server.queuedResponseCount, 0);
    });

    test("Mock Server respects delays for queued requests", () async {
      server.queueResponse(new Response.ok(null), delay: new Duration(milliseconds: 500));

      var responseReturned = false;
      var responseFuture = testClient.request("/hello").get();
      responseFuture.whenComplete(() => responseReturned = true);

      await new Future.delayed(new Duration(milliseconds: 400));
      expect(responseReturned, false);
      await new Future.delayed(new Duration(milliseconds: 200));
      expect(responseReturned, true);
    });

    test("Mock server uses default delay for requests without an explicit delay", () async {
      server.queueResponse(new Response.ok(null));
      server.defaultDelay = new Duration(milliseconds: 300);

      var responseReturned = false;
      var responseFuture = testClient.request("/hello").get();
      responseFuture.whenComplete(() => responseReturned = true);

      await new Future.delayed(new Duration(milliseconds: 200));
      expect(responseReturned, false);
      await new Future.delayed(new Duration(milliseconds: 200));
      expect(responseReturned, true);

      server.queueResponse(new Response.ok(null), delay: new Duration(milliseconds: 600));

      responseReturned = false;
      responseFuture = testClient.request("/hello").get();
      responseFuture.whenComplete(() => responseReturned = true);

      await new Future.delayed(new Duration(milliseconds: 500));
      expect(responseReturned, false);
      await new Future.delayed(new Duration(milliseconds: 200));
      expect(responseReturned, true);
    });

    test("Default response respects default delay", () async {
      server.defaultDelay = new Duration(milliseconds: 300);

      var responseReturned = false;
      var responseFuture = testClient.request("/hello").get();
      responseFuture.whenComplete(() => responseReturned = true);

      await new Future.delayed(new Duration(milliseconds: 200));
      expect(responseReturned, false);
      await new Future.delayed(new Duration(milliseconds: 200));
      expect(responseReturned, true);
    });
  });
}

Future spawnFunc(List pair) async {
  final path = pair.first;
  final delay = pair.last;
  final testClient = new TestClient.onPort(4000);
  sleep(new Duration(seconds: delay));
  await testClient.request(path).get();
}
