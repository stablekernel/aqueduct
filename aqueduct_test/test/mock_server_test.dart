import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';

void main() {
  group("Mock HTTP Tests", () {
    MockHTTPServer server;
    final testClient = Agent.onPort(4000);

    setUp(() async {
      server = MockHTTPServer(4000);
      await server.open();
    });

    tearDown(() async {
      await server.close();
    });

    test("Request body is captured", () async {
      await testClient.put("/foo", body: {"a": "b"});

      final serverRequest = await server.next();
      expect(serverRequest.method, "PUT");
      expect(serverRequest.body.as<Map>()["a"], "b");
      // expectRequest(serverRequest, method: "PUT", body: {"a": "b"});
    });

    test("Request is enqueued and immediately available", () async {
      await testClient.get("/hello", query: {"foo": "bar"}, headers: {"X": "Y"});

      final serverRequest = await server.next();
      expect(serverRequest.method, "GET");
      expect(serverRequest.path.string, "/hello");
      expect(serverRequest.raw.uri.queryParameters["foo"], "bar");
      expect(serverRequest.raw.headers.value("x"), "Y");

      // expectRequest(serverRequest, method: "GET", path: "/hello", query: {"foo" : "bar"}, headers: {"x": "Y"});
    });

    test("Wait for request that will happen in future", () async {
      final i1 = await Isolate.spawn(spawnFunc, ["/foo", 1], paused: true);
      final i2 = await Isolate.spawn(spawnFunc, ["/bar", 2], paused: true);

      i1.resume(i1.pauseCapability);
      i2.resume(i2.pauseCapability);

      var serverRequest = await server.next();
      expect(serverRequest.path.string, "/foo");
      serverRequest = await server.next();
      expect(serverRequest.path.string, "/bar");
    });

    test("Clear and empty", () async {
      await (testClient.request("/hello?foo=bar")..headers = {"X": "Y"}).get();
      expect(server.isEmpty, false);
      server.clear();
      expect(server.isEmpty, true);
    });

    test(
        "Mock server returns an error by default if there are no enqueued requests",
        () async {
      final response = await testClient.request("/hello").get();
      expect(response.statusCode, 503);
    });

    test("Mock server default response can be changed", () async {
      server.defaultResponse =
          Response.ok({"key": "This is the default response"});

      final response = await testClient.request("/hello").get();
      expect(response,
          hasResponse(200, body: {"key": "This is the default response"}));
    });

    test("Queued response count returns correct number of queued requests",
        () async {
      expect(server.queuedResponseCount, 0);
      server.queueResponse(Response.ok(null));
      expect(server.queuedResponseCount, 1);
      server.queueResponse(Response.unauthorized());
      expect(server.queuedResponseCount, 2);
      await testClient.request("/hello").get();
      expect(server.queuedResponseCount, 1);
      await testClient.request("/hello").post();
      expect(server.queuedResponseCount, 0);
      await testClient.request("/hello").get(); // Returns default response
      expect(server.queuedResponseCount, 0);
    });

    test("Mock Server respects delays for queued requests", () async {
      server.queueResponse(Response.ok(null),
          delay: Duration(milliseconds: 1000));

      var responseReturned = false;
      final responseFuture = testClient.request("/hello").get();
      // ignore: unawaited_futures
      responseFuture.whenComplete(() => responseReturned = true);

      await Future.delayed(Duration(milliseconds: 100));
      expect(responseReturned, false);
      await Future.delayed(Duration(milliseconds: 1500));
      expect(responseReturned, true);
    });

    test(
        "Mock server uses default delay for requests without an explicit delay",
        () async {
      server.defaultDelay = Duration(milliseconds: 1000);
      server.queueResponse(Response.ok(null));

      var responseReturned = false;
      var responseFuture = testClient.request("/hello").get();
      // ignore: unawaited_futures
      responseFuture.whenComplete(() => responseReturned = true);

      await Future.delayed(Duration(milliseconds: 100));
      expect(responseReturned, false);
      await Future.delayed(Duration(milliseconds: 1500));
      expect(responseReturned, true);

      server.queueResponse(Response.ok(null),
          delay: Duration(milliseconds: 1000));

      responseReturned = false;
      responseFuture = testClient.request("/hello").get();
      // ignore: unawaited_futures
      responseFuture.whenComplete(() => responseReturned = true);

      await Future.delayed(Duration(milliseconds: 100));
      expect(responseReturned, false);
      await Future.delayed(Duration(milliseconds: 1500));
      expect(responseReturned, true);
    });

    test("Default response respects default delay", () async {
      server.defaultDelay = Duration(milliseconds: 1000);

      var responseReturned = false;
      final responseFuture = testClient.request("/hello").get();
      // ignore: unawaited_futures
      responseFuture.whenComplete(() => responseReturned = true);

      await Future.delayed(Duration(milliseconds: 100));
      expect(responseReturned, false);
      await Future.delayed(Duration(milliseconds: 1500));
      expect(responseReturned, true);
    });

    test("Can provide a single outage", () async {
      server.queueOutage();
      server.queueResponse(Response.ok(null));
      final outageResponseFuture = testClient.request("/outage").get();

      // Introduce a delay to ensure that the /outage request gets there before /success
      await Future.delayed(Duration(seconds: 1));
      final successResponse = await testClient.request("/success").get();

      expect(successResponse.statusCode, 200);

      expect(
          outageResponseFuture.timeout(Duration(milliseconds: 100),
              onTimeout: () {}),
          completes);
    });

    test("Can provide multiple outages", () async {
      server.queueOutage(count: 2);
      server.queueOutage();
      server.queueResponse(Response.ok(null));
      final outageResponseFuture1 = testClient.request("/outage").get();
      final outageResponseFuture2 = testClient.request("/outage").get();
      final outageResponseFuture3 = testClient.request("/outage").get();

      // Introduce a delay to ensure that the /outage request gets there before /success
      await Future.delayed(Duration(seconds: 1));
      final successResponse = await testClient.request("/success").get();

      expect(successResponse.statusCode, 200);

      expect(outageResponseFuture1, doesNotComplete);
      expect(outageResponseFuture2, doesNotComplete);
      expect(outageResponseFuture3, doesNotComplete);
    });

    test("Can queue handler", () async {
      server.queueHandler(
          (req) => Response.ok({"k": req.raw.uri.queryParameters["k"]}));
      final response = await testClient.request("/ok?k=1").get();
      expect(response.body.as<Map>()["k"], "1");

      expect((await testClient.request("/ok").get()).statusCode,
          server.defaultResponse.statusCode);
    });
  });
}

Future spawnFunc(List pair) async {
  final path = pair.first as String;
  final delay = pair.last as int;
  final testClient = Agent.onPort(4000);
  sleep(Duration(seconds: delay));
  await testClient.request(path).get().catchError((_) => null);

}
