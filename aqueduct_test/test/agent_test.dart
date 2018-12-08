import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';

void main() {
  group("Agent instantiation", () {
    Application app;

    tearDown(() async {
      await app?.stop();
    });

    test("Create from app, explicit port", () async {
      app = Application<SomeChannel>()..options.port = 4111;
      await app.startOnCurrentIsolate();
      final client = Agent(app);
      expect(client.baseURL, "http://localhost:4111");
    });

    test("Create from app, assigned port", () async {
      app = Application<SomeChannel>()..options.port = 0;
      await app.startOnCurrentIsolate();

      final client = Agent(app);
      final response = await client.request("/").get();
      expect(response, hasStatus(200));
    });

    test("Create from unstarted app throws useful exception", () async {
      app = Application<SomeChannel>();
      final tc = Agent(app);
      try {
        await tc.request("/").get();
        expect(true, false);
      } on StateError catch (e) {
        expect(e.toString(), contains("Application under test is not running"));
      }
    });

    test("Create from unstarted app, start app, works OK", () async {
      app = Application<SomeChannel>()..options.port = 0;
      final tc = Agent(app);
      await app.startOnCurrentIsolate();

      expectResponse(await tc.request("/").get(), 200);
    });

    test(
        "Create agent from another agent has same request URL, contentType and headers",
        () {
      final original = Agent.fromOptions(ApplicationOptions()
        ..port = 2121
        ..address = "foobar.com");
      original.headers["key"] = "value";
      original.contentType = ContentType.text;

      final clone = Agent.from(original);
      expect(clone.baseURL, original.baseURL);
      expect(clone.headers, original.headers);
      expect(clone.contentType, original.contentType);
    });
  });

  group("Request building", () {
    final server = MockHTTPServer(4040);
    setUp(() async {
      await server.open();
    });

    tearDown(() async {
      await server?.close();
    });

    test("Host created correctly", () {
      final defaultTestClient = Agent.onPort(4040);
      final portConfiguredClient =
          Agent.fromOptions(ApplicationOptions()..port = 2121);
      final hostPortConfiguredClient = Agent.fromOptions(ApplicationOptions()
        ..port = 2121
        ..address = "foobar.com");
      final hostPortSSLConfiguredClient = Agent.fromOptions(
          ApplicationOptions()
            ..port = 2121
            ..address = "foobar.com",
          useHTTPS: true);
      expect(defaultTestClient.baseURL, "http://localhost:4040");
      expect(portConfiguredClient.baseURL, "http://localhost:2121");
      expect(hostPortConfiguredClient.baseURL, "http://localhost:2121");
      expect(hostPortSSLConfiguredClient.baseURL, "https://localhost:2121");
    });

    test("Request URLs are created correctly", () {
      final defaultTestClient = Agent.onPort(4040);

      expect(defaultTestClient.request("/foo").requestURL,
          "http://localhost:4040/foo");
      expect(defaultTestClient.request("foo").requestURL,
          "http://localhost:4040/foo");
      expect(defaultTestClient.request("foo/bar").requestURL,
          "http://localhost:4040/foo/bar");

      expect(
          (defaultTestClient.request("/foo")..query = {"baz": "bar"})
              .requestURL,
          "http://localhost:4040/foo?baz=bar");
      expect((defaultTestClient.request("/foo")..query = {"baz": 2}).requestURL,
          "http://localhost:4040/foo?baz=2");
      expect(
          (defaultTestClient.request("/foo")..query = {"baz": null}).requestURL,
          "http://localhost:4040/foo?baz");
      expect(
          (defaultTestClient.request("/foo")..query = {"baz": true}).requestURL,
          "http://localhost:4040/foo?baz");
      expect(
          (defaultTestClient.request("/foo")..query = {"baz": true, "boom": 7})
              .requestURL,
          "http://localhost:4040/foo?baz&boom=7");
    });

    test("HTTP requests are issued", () async {
      final defaultTestClient = Agent.onPort(4040);
      expect(await defaultTestClient.request("/foo").get() is TestResponse,
          true);
      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "GET");

      expect(await defaultTestClient.request("/foo").delete() is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "DELETE");

      expect(
          await defaultTestClient.post("/foo", body: {"foo": "bar"})
              is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "POST");
      expect(msg.body.as(), {"foo": "bar"});

      expect(
          await defaultTestClient
              .execute("PATCH", "/foo", body: {"foo": "bar"}) is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PATCH");
      expect(msg.body.as(), {"foo": "bar"});

      expect(
          await defaultTestClient.put("/foo", body: {"foo": "bar"})
              is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PUT");
      expect(msg.body.as<Map<String, dynamic>>(), {"foo": "bar"});
    });

    test("Default headers are added to requests", () async {
      final defaultTestClient = Agent.onPort(4040)
        ..headers["X-Int"] = 1
        ..headers["X-String"] = "1";

      await defaultTestClient.get("/foo");

      final msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("x-int"), "1");
      expect(msg.raw.headers.value("x-string"), "1");
    });

    test("Default headers can be overridden", () async {
      final defaultTestClient = Agent.onPort(4040)
        ..headers["X-Int"] = 1
        ..headers["X-String"] = "1";

      await (defaultTestClient.request("/foo")
            ..headers = {
              "X-Int": [1, 2]
            })
          .get();

      final msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("x-int"), "1, 2");
    });

    test("Client can expect array of JSON", () async {
      final client = Agent.onPort(8888);
      final server = await HttpServer.bind("localhost", 8888,
          v6Only: false, shared: false);
      final router = Router();
      router.route("/na").link(() => TestController());
      router.didAddToChannel();
      server.map((req) => Request(req)).listen(router.receive);

      final resp = await client.request("/na").get();
      expect(
          resp, hasResponse(200, body: everyElement({"id": greaterThan(0)})));

      await server?.close(force: true);
    });

    test("Query parameters are provided when using execute", () async {
      final defaultTestClient = Agent.onPort(4040);

      await defaultTestClient.get("/foo", query: {"k": "v"});

      final msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.uri.query, "k=v");
    });

    test("Basic authorization adds header to all requests", () async {
      final defaultTestClient = Agent.onPort(4040)
        ..headers["k"] = "v"
        ..setBasicAuthorization("username", "password");

      await defaultTestClient.get("/foo");

      final msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("k"), "v");
      expect(msg.raw.headers.value("authorization"),
          "Basic ${base64.encode("username:password".codeUnits)}");
    });

    test("Bearer authorization adds header to all requests", () async {
      final defaultTestClient = Agent.onPort(4040)
        ..headers["k"] = "v"
        ..bearerAuthorization = "token";

      await defaultTestClient.get("/foo");

      final msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("k"), "v");
      expect(msg.raw.headers.value("authorization"), "Bearer token");
    });
  });

  group("Response handling", () {
    HttpServer server;

    tearDown(() async {
      await server.close(force: true);
    });

    test("Responses have body", () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4000);
      server.listen((req) {
        final resReq = Request(req);
        resReq.respond(Response.ok([
          {"a": "b"}
        ]));
      });

      final defaultTestClient = Agent.onPort(4000);
      final response = await defaultTestClient.request("/foo").get();
      expect(response.body.as<List>().length, 1);
      expect(response.body.as<List>().first["a"], "b");
    });

    test("Responses with no body don't return one", () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4000);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.close();
      });

      final defaultTestClient = Agent.onPort(4000);
      final response = await defaultTestClient.request("/foo").get();
      expect(response.body.isEmpty, true);
    });

    test("Request with accept adds header", () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4000);
      server.listen((req) {
        final resReq = Request(req);
        resReq.respond(Response.ok(
            {"ACCEPT": req.headers.value(HttpHeaders.acceptHeader)}));
      });

      final  client = Agent.onPort(4000);
      final  req = client.request("/foo")
        ..accept = [ContentType.json, ContentType.text];

      final response = await req.post();
      expect(response.body.as<Map<String, dynamic>>(), {
        "ACCEPT": "application/json; charset=utf-8,text/plain; charset=utf-8"
      });
    });
  });
}

class SomeChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final r = Router();
    r.route("/").linkFunction((r) async => Response.ok(null));
    return r;
  }
}

class TestController extends ResourceController {
  @Operation.get()
  Future<Response> get() async {
    return Response.ok([
      {"id": 1},
      {"id": 2}
    ]);
  }
}
