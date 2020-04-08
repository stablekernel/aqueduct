import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  HttpServer server;

  tearDown(() async {
    await server?.close();
  });

  test("Response thrown during normal handling is sent as response", () async {
    server = await enableController(ClosureController((req) {
      throw Response.ok(null);
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 200);
  });

  test("Unknown error thrown during handling returns 500", () async {
    server = await enableController(ClosureController((req) {
      throw StateError("error");
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 500);
  });

  test("HandlerException thrown in handle returns its response", () async {
    server = await enableController(ClosureController((req) {
      throw HandlerException(Response.ok(null));
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 200);
  });

  test("Throw exception when sending HandlerException response sends 500",
      () async {
    server = await enableController(ClosureController((req) {
      throw CrashingTestHandlerException();
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 500);
  });

  test("Throw exception when sending thrown Response sends 500", () async {
    server = await enableController(ClosureController((req) {
      // nonsense body to trigger exception when encoding
      throw Response.ok(PassthruController());
    }));

    final r = await http.get("http://localhost:4040");
    expect(r.statusCode, 500);
  });
}

Future<HttpServer> enableController(Controller controller) async {
  var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4040);

  controller.didAddToChannel();

  server.map((httpReq) => Request(httpReq)).listen(controller.receive);

  return server;
}

class CrashingTestHandlerException implements HandlerException {
  @override
  Response get response => throw StateError("");
}

typedef ClosureHandler = FutureOr<RequestOrResponse> Function(Request request);

class ClosureController extends Controller {
  ClosureController(this.handler);
  final ClosureHandler handler;

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return handler(request);
  }
}