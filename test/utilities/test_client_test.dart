import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:isolate';
import 'dart:io';
import 'dart:async';

void main() {
  group("Test Client/Request/Response", () {
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

    test("Headers are added correctly", () async {
      var defaultTestClient = new TestClient(4040);

      await (defaultTestClient.request("/foo")
        ..headers = {"X-Content" : 1}).get();

      var msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.headers["x-content"], "1");

    });
  });

  group("Matchers", () {

  });
}