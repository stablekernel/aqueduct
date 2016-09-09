import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:mirrors';
import 'dart:isolate';

void main() {
  HttpServer server = null;
  tearDown(() async {
    await server.close();
  });

  test("Logging after socket is closed does not throw exception", () async {
    var handler = new RequestHandler(requestHandler: (ResourceRequest req) {
      req.innerRequest.response.detachSocket().then((s) async {
        s.destroy();

        req.toDebugString(includeHeaders: true, includeBody: true, includeContentSize: true,
            includeElapsedTime: true, includeMethod: true, includeRequestIP: true, includeResource: true,
            includeStatusCode: true);
      });
    });

    var ensureExceptionIsCapturedByDeliver = new Completer();
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server
        .map((req) => new ResourceRequest(req))
        .listen((req) async {
      await handler.deliver(req);

      // We won't get here unless an exception is thrown, and that's what we're testing
      ensureExceptionIsCapturedByDeliver.complete(true);
    });

    try {
      await http.get("http://localhost:8000");
    } catch (e) {}

    expect(ensureExceptionIsCapturedByDeliver.future, completes);
  });

  test("Request handler that dies on bad state: header already sent is captured in RequestHandler", () async {
    var handler = new RequestHandler(requestHandler: (ResourceRequest req) {
      req.response.close();

      return new Response.ok(null);
    });

    var ensureExceptionIsCapturedByDeliver = new Completer();
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server
        .map((req) => new ResourceRequest(req))
        .listen((req) async {
      await handler.deliver(req);

      // We won't get here unless an exception is thrown, and that's what we're testing
      ensureExceptionIsCapturedByDeliver.complete(true);
    });

    await http.get("http://localhost:8000");

    expect(ensureExceptionIsCapturedByDeliver.future, completes);
  });

  test("Request handler throwing HttpResponseException that dies on bad state: header already sent is captured in RequestHandler", () async {
    var handler = new RequestHandler(requestHandler: (ResourceRequest req) {
      req.response.close();

      throw new HttpResponseException(400, "whocares");
    });

    var ensureExceptionIsCapturedByDeliver = new Completer();
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server
        .map((req) => new ResourceRequest(req))
        .listen((req) async {
      await handler.deliver(req);

      // We won't get here unless an exception is thrown, and that's what we're testing
      ensureExceptionIsCapturedByDeliver.complete(true);
    });

    await http.get("http://localhost:8000");

    expect(ensureExceptionIsCapturedByDeliver.future, completes);
  });
}