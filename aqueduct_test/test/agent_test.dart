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
      app = new Application<SomeChannel>()..options.port = 4111;
      await app.startOnCurrentIsolate();
      var client = new Agent(app);
      expect(client.baseURL, "http://localhost:4111");
    });

    test("Create from app, assigned port", () async {
      app = new Application<SomeChannel>()..options.port = 0;
      await app.startOnCurrentIsolate();

      var client = new Agent(app);
      var response = await client.request("/").get();
      expect(response, hasStatus(200));
    });

    test("Create from unstarted app throws useful exception", () async {
      app = new Application<SomeChannel>();
      var tc = new Agent(app);
      try {
        await tc.request("/").get();
        expect(true, false);
      } on StateError catch (e) {
        expect(e.toString(), contains("Application under test is not running"));
      }
    });

    test("Create from unstarted app, start app, works OK", () async {
      app = new Application<SomeChannel>()..options.port = 0;
      var tc = new Agent(app);
      await app.startOnCurrentIsolate();

      expectResponse(await tc.request("/").get(), 200);
    });

    test("Create agent from another agent has same request URL, contentType and headers", () {
      final original = new Agent.fromOptions(new ApplicationOptions()
        ..port = 2121
        ..address = "foobar.com");
      original.headers["key"] = "value";
      original.contentType = ContentType.text;

      final clone = new Agent.from(original);
      expect(clone.baseURL, original.baseURL);
      expect(clone.headers, original.headers);
      expect(clone.contentType, original.contentType);
    });
  });

  group("Request building", () {
    var server = new MockHTTPServer(4040);
    setUp(() async {
      await server.open();
    });

    tearDown(() async {
      await server?.close();
    });

    test("Host created correctly", () {
      var defaultTestClient = new Agent.onPort(4040);
      var portConfiguredClient = new Agent.fromOptions(new ApplicationOptions()..port = 2121);
      var hostPortConfiguredClient = new Agent.fromOptions(new ApplicationOptions()
        ..port = 2121
        ..address = "foobar.com");
      var hostPortSSLConfiguredClient = new Agent.fromOptions(
          new ApplicationOptions()
            ..port = 2121
            ..address = "foobar.com",
          useHTTPS: true);
      expect(defaultTestClient.baseURL, "http://localhost:4040");
      expect(portConfiguredClient.baseURL, "http://localhost:2121");
      expect(hostPortConfiguredClient.baseURL, "http://localhost:2121");
      expect(hostPortSSLConfiguredClient.baseURL, "https://localhost:2121");
    });

    test("Request URLs are created correctly", () {
      var defaultTestClient = new Agent.onPort(4040);

      expect(defaultTestClient.request("/foo").requestURL, "http://localhost:4040/foo");
      expect(defaultTestClient.request("foo").requestURL, "http://localhost:4040/foo");
      expect(defaultTestClient.request("foo/bar").requestURL, "http://localhost:4040/foo/bar");

      expect(
          (defaultTestClient.request("/foo")..query = {"baz": "bar"}).requestURL, "http://localhost:4040/foo?baz=bar");
      expect((defaultTestClient.request("/foo")..query = {"baz": 2}).requestURL, "http://localhost:4040/foo?baz=2");
      expect((defaultTestClient.request("/foo")..query = {"baz": null}).requestURL, "http://localhost:4040/foo?baz");
      expect((defaultTestClient.request("/foo")..query = {"baz": true}).requestURL, "http://localhost:4040/foo?baz");
      expect((defaultTestClient.request("/foo")..query = {"baz": true, "boom": 7}).requestURL,
          "http://localhost:4040/foo?baz&boom=7");
    });

    test("HTTP requests are issued", () async {
      var defaultTestClient = new Agent.onPort(4040);
      expect((await defaultTestClient.request("/foo").get()) is TestResponse, true);
      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "GET");

      expect((await defaultTestClient.request("/foo").delete()) is TestResponse, true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "DELETE");

      expect((await defaultTestClient.post("/foo", body: {"foo": "bar"})) is TestResponse, true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "POST");
      expect(msg.body.as(), {"foo": "bar"});

      expect((await defaultTestClient.execute("PATCH", "/foo", body: {"foo": "bar"})) is TestResponse, true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PATCH");
      expect(msg.body.as(), {"foo": "bar"});

      expect((await defaultTestClient.put("/foo", body: {"foo": "bar"})) is TestResponse, true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PUT");
      expect(msg.body.as<Map<String, dynamic>>(), {"foo": "bar"});
    });

    test("Default headers are added to requests", () async {
      var defaultTestClient = new Agent.onPort(4040)
        ..headers["X-Int"] = 1
        ..headers["X-String"] = "1";

      await defaultTestClient.get("/foo");

      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("x-int"), "1");
      expect(msg.raw.headers.value("x-string"), "1");
    });

    test("Default headers can be overridden", () async {
      var defaultTestClient = new Agent.onPort(4040)
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
      Agent client = new Agent.onPort(8888);
      HttpServer server = await HttpServer.bind("localhost", 8888, v6Only: false, shared: false);
      var router = new Router();
      router.route("/na").link(() => new TestController());
      router.didAddToChannel();
      server.map((req) => new Request(req)).listen(router.receive);

      var resp = await client.request("/na").get();
      expect(resp, hasResponse(200, body: everyElement({"id": greaterThan(0)})));

      await server?.close(force: true);
    });

    test("Query parameters are provided when using execute", () async {
      var defaultTestClient = new Agent.onPort(4040);

      await defaultTestClient.get("/foo", query: {"k": "v"});

      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.uri.query, "k=v");
    });

    test("Basic authorization adds header to all requests", () async {
      var defaultTestClient = new Agent.onPort(4040)
        ..headers["k"] = "v"
        ..setBasicAuthorization("username", "password");

      await defaultTestClient.get("/foo");

      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("k"), "v");
      expect(msg.raw.headers.value("authorization"), "Basic ${base64.encode("username:password".codeUnits)}");
    });

    test("Bearer authorization adds header to all requests", () async {
      var defaultTestClient = new Agent.onPort(4040)
        ..headers["k"] = "v"
        ..bearerAuthorization = "token";

      await defaultTestClient.get("/foo");

      var msg = await server.next();
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
        var resReq = new Request(req);
        resReq.respond(new Response.ok([
          {"a": "b"}
        ]));
      });

      var defaultTestClient = new Agent.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response.body.as<List>().length, 1);
      expect(response.body.as<List>().first["a"], "b");
    });

    test("Responses with no body don't return one", () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4000);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.close();
      });

      var defaultTestClient = new Agent.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response.body.isEmpty, true);
    });

    test("Request with accept adds header", () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4000);
      server.listen((req) {
        var resReq = new Request(req);
        resReq.respond(new Response.ok({"ACCEPT": req.headers.value(HttpHeaders.acceptHeader)}));
      });

      var client = new Agent.onPort(4000);
      var req = client.request("/foo")..accept = [ContentType.json, ContentType.text];

      var response = await req.post();
      expect(response.body.as<Map<String, dynamic>>(), {"ACCEPT": "application/json; charset=utf-8,text/plain; charset=utf-8"});
    });
  });
}

class SomeChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final r = new Router();
    r.route("/").linkFunction((r) async => new Response.ok(null));
    return r;
  }
}

class TestController extends ResourceController {
  @Operation.get()
  Future<Response> get() async {
    return new Response.ok([
      {"id": 1},
      {"id": 2}
    ]);
  }
}
