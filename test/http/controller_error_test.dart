import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;

void main() {
  HttpServer server;

  tearDown(() async {
    await server?.close();
  });

  test("Response thrown during normal handling is sent as response", () async {
    server = await enableController(new Controller((req) {
      throw new Response.ok(null);
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 200);
  });

  test("Unknown error thrown during handling returns 500", () async {
    server = await enableController(new Controller((req) {
      throw new StateError("error");
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 500);
  });

  test("HandlerException thrown in handle returns its response", () async {
    server = await enableController(new Controller((req) {
      throw new HandlerException(new Response.ok(null));
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 200);
  });

  test("Throw exception when sending HandlerException response sends 500", () async {
    server = await enableController(new Controller((req) {
      throw new CrashingTestHandlerException();
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 500);
  });

  test("Throw exception when sending thrown Response sends 500", () async {
    server = await enableController(new Controller((req) {
      // nonsense body to trigger exception when encoding
      throw new Response.ok(new Controller());
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 500);
  });
}

Future<HttpServer> enableController(Controller controller) async {
  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4040);
  controller.didAddToChannel();

  server.map((httpReq) => new Request(httpReq)).listen(controller.receive);

  return server;
}

class CrashingTestHandlerException implements HandlerException {
  @override
  Response get response => throw new StateError("");
}