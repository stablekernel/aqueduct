import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

// Some CachePolicy fields are tested by file_controller_test.dart, this
// file tests the combinations not tested there.
void main() {
  HttpServer server;

  tearDown(() async {
    await server?.close(force: true);
  });

  test("Prevent intermediate caching", () async {
    var policy = const CachePolicy(preventIntermediateProxyCaching: true);
    server = await bindAndRespondWith(Response.ok("foo")..cachePolicy = policy);
    var result = await http.get("http://localhost:8888/");
    expect(result.headers["cache-control"], "private");
  });

  test("Prevent caching altogether", () async {
    var policy = const CachePolicy(preventCaching: true);
    server = await bindAndRespondWith(Response.ok("foo")..cachePolicy = policy);
    var result = await http.get("http://localhost:8888/");
    expect(result.headers["cache-control"], "no-cache, no-store");
  });
}

Future<HttpServer> bindAndRespondWith(Response response) async {
  var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
  server.map((req) => Request(req)).listen((req) async {
    var next = PassthruController();
    next.linkFunction((req) async {
      return response;
    });
    await next.receive(req);
  });

  return server;
}
