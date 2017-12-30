import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/test.dart';
import 'dart:convert';

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
      app = new Application<SomeChannel>()
          ..options.port = 4111;
      await app.test();
      var client = new TestClient(app);
      expect(client.baseURL, "http://localhost:4111");
    });

    test("Create from app, assigned port", () async {
      app = new Application<SomeChannel>()
        ..options.port = 0;
      await app.test();

      var client = new TestClient(app);
      var response = await client.request("/").get();
      expect(response, hasStatus(200));
    });

    test("Create from unstarted app throws useful exception", () async {
      app = new Application<SomeChannel>();
      var tc = new TestClient(app);
      try {
        await tc.request("/").get();
        expect(true, false);
      } on TestClientException catch (e) {
        expect(e.toString(), contains("Application under test is not running"));
      }
    });

    test("Create from unstarted app, start app, works OK", () async {
      app = new Application<SomeChannel>()
        ..options.port = 0;
      var tc = new TestClient(app);
      await app.test();

      expectResponse(await tc.request("/").get(), 200);
    });

    test("Host created correctly", () {
      var defaultTestClient = new TestClient.onPort(4040);
      var portConfiguredClient = new TestClient.fromOptions(
          new ApplicationOptions()..port = 2121);
      var hostPortConfiguredClient =
          new TestClient.fromOptions(new ApplicationOptions()
            ..port = 2121
            ..address = "foobar.com");
      var hostPortSSLConfiguredClient =
          new TestClient.fromOptions(new ApplicationOptions()
            ..port = 2121
            ..address = "foobar.com", useHTTPS: true);
      expect(defaultTestClient.baseURL, "http://localhost:4040");
      expect(portConfiguredClient.baseURL, "http://localhost:2121");
      expect(hostPortConfiguredClient.baseURL, "http://localhost:2121");
      expect(hostPortSSLConfiguredClient.baseURL, "https://localhost:2121");
    });

    test("Request URLs are created correctly", () {
      var defaultTestClient = new TestClient.onPort(4040);

      expect(defaultTestClient.request("/foo").requestURL,
          "http://localhost:4040/foo");
      expect(defaultTestClient.request("foo").requestURL,
          "http://localhost:4040/foo");
      expect(defaultTestClient.request("foo/bar").requestURL,
          "http://localhost:4040/foo/bar");

      expect(
          (defaultTestClient.request("/foo")..queryParameters = {"baz": "bar"})
              .requestURL,
          "http://localhost:4040/foo?baz=bar");
      expect(
          (defaultTestClient.request("/foo")..queryParameters = {"baz": 2})
              .requestURL,
          "http://localhost:4040/foo?baz=2");
      expect(
          (defaultTestClient.request("/foo")..queryParameters = {"baz": null})
              .requestURL,
          "http://localhost:4040/foo?baz");
      expect(
          (defaultTestClient.request("/foo")..queryParameters = {"baz": true})
              .requestURL,
          "http://localhost:4040/foo?baz");
      expect(
          (defaultTestClient.request("/foo")
                ..queryParameters = {"baz": true, "boom": 7})
              .requestURL,
          "http://localhost:4040/foo?baz&boom=7");
    });

    test("HTTP requests are issued", () async {
      var defaultTestClient = new TestClient.onPort(4040);
      expect((await defaultTestClient.request("/foo").get()) is TestResponse,
          true);
      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "GET");

      expect((await defaultTestClient.request("/foo").delete()) is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "DELETE");

      expect(
          (await (defaultTestClient.request("/foo")..json = {"foo": "bar"})
              .post()) is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "POST");
      expect(msg.body.asMap(), {"foo":"bar"});

      expect(
          (await (defaultTestClient.request("/foo")..json = {"foo": "bar"})
              .method("PATCH")) is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PATCH");
      expect(msg.body.asMap(), {"foo":"bar"});

      expect(
          (await (defaultTestClient.request("/foo")..json = {"foo": "bar"})
              .put()) is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "PUT");
      expect(msg.body.asMap(), {"foo":"bar"});
    });

    test("Client authenticated requests add credentials", () async {
      var defaultTestClient = new TestClient.onPort(4040)
        ..clientID = "a"
        ..clientSecret = "b";
      expect(
          (await defaultTestClient.clientAuthenticatedRequest("/foo").get())
              is TestResponse,
          true);
      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "GET");

      var auth = new Base64Encoder().convert("a:b".codeUnits);
      expect(msg.raw.headers.value("authorization"), "Basic $auth");
    });

    test("Default public client authenticated requests add credentials", () async {
      var defaultTestClient = new TestClient.onPort(4040)
        ..clientID = "a";
      expect(
          (await defaultTestClient.clientAuthenticatedRequest("/foo").get())
          is TestResponse,
          true);
      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "GET");

      var auth = new Base64Encoder().convert("a:".codeUnits);
      expect(msg.raw.headers.value("authorization"), "Basic $auth");
    });

    test("Public client authenticated requests add credentials", () async {
      var defaultTestClient = new TestClient.onPort(4040);
      expect(
          (await defaultTestClient.clientAuthenticatedRequest("/foo", clientID: "a").get())
          is TestResponse,
          true);
      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "GET");

      var auth = new Base64Encoder().convert("a:".codeUnits);
      expect(msg.raw.headers.value("authorization"), "Basic $auth");
    });

    test("Bearer requests add credentials", () async {
      var defaultTestClient = new TestClient.onPort(4040)
        ..defaultAccessToken = "abc";
      expect(
          (await defaultTestClient.authenticatedRequest("/foo").get())
              is TestResponse,
          true);
      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.method, "GET");
      expect(msg.raw.headers.value("authorization"), "Bearer abc");
    });

    test("Headers are added correctly", () async {
      var defaultTestClient = new TestClient.onPort(4040);

      await (defaultTestClient.request("/foo")..headers = {"X-Content": 1})
          .get();

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

    test("Form data is in query string if GET", () async {
      var data = {"a": "b/b"};

      var defaultTestClient = new TestClient.onPort(4040);

      await (defaultTestClient.request("/foo")..formData = data).get();

      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.uri.queryParameters, {"a": "b/b"});
      expect(msg.body.isEmpty, true);
    });

    test("Form data is in body if POST", () async {
      var data = {"a": "b/b"};

      var defaultTestClient = new TestClient.onPort(4040);

      await (defaultTestClient.request("/foo")..formData = data).post();

      var msg = await server.next();
      expect(msg.path.string, "/foo");
      expect(msg.raw.uri.queryParameters, {});
      expect(msg.body.asMap(), {
        "a": ["b/b"]
      });
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

      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response.asList.length, 1);
      expect(response.asList.first["a"], "b");
    });

    test("Responses with no body don't return one", () async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4000);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.close();
      });

      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response.body, isNull);
    });

    test("Request with accept adds header", () async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4000);
      server.listen((req) {
        var resReq = new Request(req);
        resReq.respond(new Response.ok({
          "ACCEPT": req.headers.value(HttpHeaders.ACCEPT)
        }));
      });

      var client = new TestClient.onPort(4000);
      var req = client.request("/foo")
        ..accept = [ContentType.JSON, ContentType.TEXT];

      var response = await req.post();
      expect(response.decodedBody, {"ACCEPT": "application/json; charset=utf-8,text/plain; charset=utf-8"});
    });
  });
}

class SomeChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final r = new Router();
    r.route("/").listen((r) async => new Response.ok(null));
    return r;
  }
}
