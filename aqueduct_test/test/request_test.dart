import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct_test/aqueduct_test.dart';

void main() {
  MockHTTPServer server;
  final agent = Agent.onPort(8000);

  setUp(() async {
    server = MockHTTPServer(8000);
    await server.open();
  });

  tearDown(() async {
    await server.close();
  });

  test("Body is encoded according to content-type, default is json", () async {
    final req = agent.request("/")..body = {"k": "v"};
    await req.post();

    final received = await server.next();
    expect(received.raw.headers.value("content-type"),
        "application/json; charset=utf-8");
    expect(received.body.as<Map>(), {"k": "v"});

    final req2 = agent.request("/")
      ..contentType = ContentType("text", "html", charset: "utf-8")
      ..body = "foobar";
    await req2.post();

    final rec2 = await server.next();
    expect(rec2.raw.headers.value("content-type"), "text/html; charset=utf-8");
    expect(rec2.body.as<String>(), "foobar");
  });

  test("If opting out of body encoding, bytes can be set directly on request",
      () async {
    final req = agent.request("/")
      ..encodeBody = false
      ..body = utf8.encode(json.encode({"k": "v"}));
    await req.post();

    final received = await server.next();
    expect(received.raw.headers.value("content-type"),
        "application/json; charset=utf-8");
    expect(received.body.as<Map>(), {"k": "v"});
  });

  test("Query parameters get URI encoded", () async {
    final req = agent.request("/")..query = {"k": "v v"};
    await req.get();

    final received = await server.next();
    expect(received.raw.uri.query, "k=v%20v");
  });

  test("Headers get added to request", () async {
    final req = agent.request("/")
      ..headers["k"] = "v"
      ..headers["i"] = 2;
    await req.get();

    final received = await server.next();
    expect(received.raw.headers.value("k"), "v");
    expect(received.raw.headers.value("i"), "2");
  });

  test("Path and baseURL negotiate path delimeters", () async {
    var req = agent.request("/")
      ..baseURL = "http://localhost:8000"
      ..path = "path";
    expect(req.requestURL, "http://localhost:8000/path");

    req = agent.request("/")
      ..baseURL = "http://localhost:8000/"
      ..path = "path";
    expect(req.requestURL, "http://localhost:8000/path");

    req = agent.request("/")
      ..baseURL = "http://localhost:8000/"
      ..path = "/path";
    expect(req.requestURL, "http://localhost:8000/path");

    req = agent.request("/")
      ..baseURL = "http://localhost:8000/base/"
      ..path = "path";
    expect(req.requestURL, "http://localhost:8000/base/path");

    req = agent.request("/")
      ..baseURL = "http://localhost:8000/base/"
      ..path = "/path";
    expect(req.requestURL, "http://localhost:8000/base/path");
  });
}
