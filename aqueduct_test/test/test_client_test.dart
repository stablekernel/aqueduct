import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';

void main() {
  group("Test Client/Request", () {
    Application app;
    var server = new MockHTTPServer(4040);
    setUp(() async {
      await server.open();
    });

    tearDown(() async {
      await app?.stop();
      await server?.close();
    });

    test("Create from app, explicit port", () async {
      app = new Application<SomeChannel>()..options.port = 4111;
      await app.test();
      var client = new Agent(app);
      expect(client.baseURL, "http://localhost:4111");
    });

    test("Create from app, assigned port", () async {
      app = new Application<SomeChannel>()..options.port = 0;
      await app.test();

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
      await app.test();

      expectResponse(await tc.request("/").get(), 200);
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

      expect((defaultTestClient.request("/foo")..query = {"baz": "bar"}).requestURL,
          "http://localhost:4040/foo?baz=bar");
      expect((defaultTestClient.request("/foo")..query = {"baz": 2}).requestURL,
          "http://localhost:4040/foo?baz=2");
      expect((defaultTestClient.request("/foo")..query = {"baz": null}).requestURL,
          "http://localhost:4040/foo?baz");
      expect((defaultTestClient.request("/foo")..query = {"baz": true}).requestURL,
          "http://localhost:4040/foo?baz");
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
      expect(msg.body.asMap(), {"foo": "bar"});

      expect((await defaultTestClient.execute("PATCH", "/foo", body: {"foo": "bar"})) is TestResponse, true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PATCH");
      expect(msg.body.asMap(), {"foo": "bar"});

      expect((await defaultTestClient.put("/foo", body: {"foo": "bar"})) is TestResponse, true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PUT");
      expect(msg.body.asMap(), {"foo": "bar"});
    });

    test("Headers are added correctly", () async {
      var defaultTestClient = new Agent.onPort(4040);

      await (defaultTestClient.request("/foo")..headers = {"X-Content": 1}).get();

      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("x-content"), "1");

      await (defaultTestClient.request("/foo")
            ..headers = {
              "X-Content": [1, 2]
            })
          .get();

      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("x-content"), "1, 2");
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

    test("Default headers are added for new request", () async {
      var c = new Agent.onPort(4040)
          ..headers["x"] = "x"
          ..headers["y"] = "y";

      await c.get("/foo", headers: {"y": "not-y"});

      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.headers.value("x"), "x");
      expect(msg.raw.headers.value("y"), "not-y");
    });
  });

  group("Test Response", () {
    HttpServer server;

    tearDown(() async {
      await server.close(force: true);
    });

    test("Responses have body", () async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4000);
      server.listen((req) {
        var resReq = new Request(req);
        resReq.respond(new Response.ok([
          {"a": "b"}
        ]));
      });

      var defaultTestClient = new Agent.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response.body.asList().length, 1);
      expect(response.body.asList().first["a"], "b");
    });

    test("Responses with no body don't return one", () async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4000);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.close();
      });

      var defaultTestClient = new Agent.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response.body.isEmpty, true);
    });

    test("Request with accept adds header", () async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4000);
      server.listen((req) {
        var resReq = new Request(req);
        resReq.respond(new Response.ok({"ACCEPT": req.headers.value(HttpHeaders.ACCEPT)}));
      });

      var client = new Agent.onPort(4000);
      var req = client.request("/foo")..accept = [ContentType.JSON, ContentType.TEXT];

      var response = await req.post();
      expect(response.body.asMap(), {"ACCEPT": "application/json; charset=utf-8,text/plain; charset=utf-8"});
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
