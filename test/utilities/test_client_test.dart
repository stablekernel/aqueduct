import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:io';
import 'dart:convert';

void main() {
  group("Test Client/Request", () {
    var server = new MockHTTPServer(4040);
    setUpAll(() async {
      await server.open();
    });

    tearDownAll(() async {
      await server?.close();
    });

    test("Host created correctly", () {
      var defaultTestClient = new TestClient(4040);
      var portConfiguredClient = new TestClient.fromConfig(new ApplicationInstanceConfiguration()..port = 2121);
      var hostPortConfiguredClient = new TestClient.fromConfig(new ApplicationInstanceConfiguration()..port = 2121..address = "foobar.com");
      var hostPortSSLConfiguredClient = new TestClient.fromConfig(new ApplicationInstanceConfiguration()..port = 2121..address = "foobar.com"..securityContext = (new SecurityContext()));
      expect(defaultTestClient.host, "http://localhost:4040");
      expect(portConfiguredClient.host, "http://localhost:2121");
      expect(hostPortConfiguredClient.host, "http://foobar.com:2121");
      expect(hostPortSSLConfiguredClient.host, "https://foobar.com:2121");
    });

    test("Request URLs are created correctly", () {
      var defaultTestClient = new TestClient(4040);

      expect(defaultTestClient.request("/foo").requestURL, "http://localhost:4040/foo");
      expect(defaultTestClient.request("foo").requestURL, "http://localhost:4040/foo");
      expect(defaultTestClient.request("foo/bar").requestURL, "http://localhost:4040/foo/bar");

      expect((defaultTestClient.request("/foo")..queryParameters = {"baz" : "bar"}).requestURL, "http://localhost:4040/foo?baz=bar");
      expect((defaultTestClient.request("/foo")..queryParameters = {"baz" : 2}).requestURL, "http://localhost:4040/foo?baz=2");
      expect((defaultTestClient.request("/foo")..queryParameters = {"baz" : null}).requestURL, "http://localhost:4040/foo?baz");
      expect((defaultTestClient.request("/foo")..queryParameters = {"baz" : true}).requestURL, "http://localhost:4040/foo?baz");
      expect((defaultTestClient.request("/foo")..queryParameters = {"baz" : true, "boom" : 7}).requestURL, "http://localhost:4040/foo?baz&boom=7");
    });

    test("HTTP requests are issued", () async {
      var defaultTestClient = new TestClient(4040);
      expect((await defaultTestClient.request("/foo").get()) is TestResponse, true);
      var msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.method, "GET");

      expect((await defaultTestClient.request("/foo").delete()) is TestResponse, true);
      msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.method, "DELETE");

      expect((await (defaultTestClient.request("/foo")..json = {"foo" : "bar"} ).post()) is TestResponse, true);
      msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.method, "POST");
      expect(msg.body, '{"foo":"bar"}');

      expect((await (defaultTestClient.request("/foo")..json = {"foo" : "bar"} ).put()) is TestResponse, true);
      msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.method, "PUT");
      expect(msg.body, '{"foo":"bar"}');
    });

    test("Headers are added correctly", () async {
      var defaultTestClient = new TestClient(4040);

      await (defaultTestClient.request("/foo")
        ..headers = {"X-Content" : 1}).get();

      var msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.headers["x-content"], "1");

      await (defaultTestClient.request("/foo")
        ..headers = {"X-Content" : [1, 2]}).get();

      msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.headers["x-content"], "1, 2");
    });
  });

  group("Test Response", () {
    test("Responses have body", () async {
      var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4000);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.JSON;
        var json = UTF8.encode(JSON.encode([{"a" : "b"}]));
        req.response.headers.contentLength = json.length;
        req.response.add(json);
        req.response.close();
      });

      var defaultTestClient = new TestClient(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response.asList.length, 1);
      expect(response.asList.first["a"], "b");

      await server.close(force: true);
    });

    test("Responses with no body don't return one", () async {
      var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4000);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.close();
      });

      var defaultTestClient = new TestClient(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response.body, isNull);

      await server.close(force: true);

    });
  });

  group("Matchers", () {

  });
}