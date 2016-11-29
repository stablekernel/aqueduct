import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:io';

void main() {
  group("Test Client/Request", () {
    var server = new MockHTTPServer(4040);
    setUp(() async {
      await server.open();
    });

    tearDown(() async {
      await server?.close();
    });

    test("Host created correctly", () {
      var defaultTestClient = new TestClient.onPort(4040);
      var portConfiguredClient = new TestClient.fromConfig(
          new ApplicationConfiguration()..port = 2121);
      var hostPortConfiguredClient =
          new TestClient.fromConfig(new ApplicationConfiguration()
            ..port = 2121
            ..address = "foobar.com");
      var hostPortSSLConfiguredClient =
          new TestClient.fromConfig(new ApplicationConfiguration()
            ..port = 2121
            ..address = "foobar.com"
            ..securityContext = (new SecurityContext()));
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
      expect(msg.path, "/foo");
      expect(msg.method, "GET");

      expect((await defaultTestClient.request("/foo").delete()) is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.method, "DELETE");

      expect(
          (await (defaultTestClient.request("/foo")..json = {"foo": "bar"})
              .post()) is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.method, "POST");
      expect(msg.body, '{"foo":"bar"}');

      expect(
          (await (defaultTestClient.request("/foo")..json = {"foo": "bar"})
              .put()) is TestResponse,
          true);
      msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.method, "PUT");
      expect(msg.body, '{"foo":"bar"}');
    });

    test("Headers are added correctly", () async {
      var defaultTestClient = new TestClient.onPort(4040);

      await (defaultTestClient.request("/foo")..headers = {"X-Content": 1})
          .get();

      var msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.headers["x-content"], "1");

      await (defaultTestClient.request("/foo")
            ..headers = {
              "X-Content": [1, 2]
            })
          .get();

      msg = await server.next();
      expect(msg.path, "/foo");
      expect(msg.headers["x-content"], "1, 2");
    });
  });

  group("Test Response", () {
    HttpServer server = null;

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
  });

  group("Matcher Basics", () {
    MockHTTPServer server = new MockHTTPServer(4000);
    setUpAll(() async {
      await server.open();
    });

    tearDownAll(() async {
      await server.close();
    });

    test("Response matcher not using response gives appropriate error", () {
      try {
        expect("foo", hasStatus(200));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(e.toString(), contains("Expected:"));
        expect(e.toString(), contains("Status Code: 200"));
        expect(e.toString(), contains("Actual: 'foo'"));
        expect(
            e.toString(),
            contains(
                "Which: Actual value is not a TestResponse, but instead String."));
      }
    });

    test("Status code matcher succeeds when correct", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasStatus(200));
    });

    test("Status code matcher fails with useful message when wrong", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();

      try {
        expect(response, hasStatus(400));
        expect(true, false);
      } on TestFailure catch (e) {
        var str = e.toString();
        expect(
            str.indexOf("Status Code: 200") > str.indexOf("Status Code: 400"),
            true);
        expect(str, contains("Headers:"));
        expect(str, contains("Body:"));
        expect(str, contains("Which: Status Code 400 != 200"));
      }
    });
  });

  group("Header matchers", () {
    HttpServer server = null;
    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4000);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.close();
      });
    });

    tearDownAll(() async {
      await server?.close(force: true);
    });

    test("Ensure existence of some headers", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(
          response,
          hasHeaders(
              {"x-frame-options": isNotNull, "content-type": isNotNull}));

      try {
        expect(response, hasHeaders({"invalid": isNotNull}));
        expect(true, false);
      } on TestFailure catch (e) {
        var string = e.toString();
        expect(string, contains("Headers: invalid: not null"));
        expect(string, contains("Status Code: 200"));
        expect(string, contains("Headers: x-frame-options"));
      }
    });

    test("Ensure values of some headers w/ matcher", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(
          response,
          hasHeaders({
            "x-frame-options": "SAMEORIGIN",
            "content-length": asNumber(lessThan(1))
          }));

      try {
        expect(response, hasHeaders({"x-frame-options": startsWith("foobar")}));
        expect(true, false);
      } on TestFailure catch (e) {
        var string = e.toString();
        expect(string, contains("Headers: x-frame-options: SAMEORIGIN"));
        expect(
            string,
            contains(
                "Headers: x-frame-options: a string starting with 'foobar'"));
      }
    });

    test("Ensure non-existence of header", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasHeaders({"invalid": isNotPresent}));

      try {
        expect(response, hasHeaders({"x-frame-options": isNotPresent}));
        expect(true, false);
      } on TestFailure catch (e) {
        var string = e.toString();
        expect(string,
            contains("Expected: Headers: x-frame-options: (Must Not Exist)"));
        expect(string, contains("Headers: x-frame-options: SAMEORIGIN"));
        expect(
            string,
            contains(
                "Which: x-frame-options must not be present, but was SAMEORIGIN"));
      }
    });

    test("Ensure any headers other than those specified", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(
          response,
          hasHeaders({
            "x-frame-options": isNotNull,
            "content-type": isNotNull,
            "x-xss-protection": startsWith("1"),
            "x-content-type-options": isNotNull,
            "content-length": asNumber(greaterThan(-1))
          }, failIfContainsUnmatchedHeader: true));

      try {
        expect(
            response,
            hasHeaders({"x-frame-options": isNotNull},
                failIfContainsUnmatchedHeader: true));
        expect(true, false);
      } on TestFailure catch (e) {
        var string = e.toString();
        expect(
            string,
            contains(
                "Header content-type was in response headers, but not part of the match set and failIfContainsUnmatchedHeader was true"));
        expect(
            string,
            contains(
                "Header x-xss-protection was in response headers, but not part of the match set and failIfContainsUnmatchedHeader was true"));
        expect(
            string,
            contains(
                "Header x-content-type-options was in response headers, but not part of the match set and failIfContainsUnmatchedHeader was true"));
        expect(
            string,
            contains(
                "Header content-length was in response headers, but not part of the match set and failIfContainsUnmatchedHeader was true"));
      }
    });
  });

  group("Body, content-type matchers", () {
    MockHTTPServer server = new MockHTTPServer(4000);
    setUp(() async {
      await server.open();
    });

    tearDown(() async {
      await server?.close();
    });

    test("Can match empty body", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok(null));
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody(isNull));

      server.queueResponse(
          new Response.ok(null, headers: {"Content-Type": "application/json"}));
      response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody(isNull));

      server.queueResponse(new Response.ok(null));
      response = await defaultTestClient.request("/foo").get();
      try {
        expect(response, hasBody(isNotNull));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(e.toString(), contains("Expected: Body: not null"));
      }
    });

    test("Can match text object", () async {
      var defaultTestClient = new TestClient.onPort(4000);

      server.queueResponse(
          new Response.ok("text")..contentType = ContentType.TEXT);
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody("text"));

      server.queueResponse(
          new Response.ok("text")..contentType = ContentType.TEXT);

      response = await defaultTestClient.request("/foo").get();
      try {
        expect(response, hasBody("foobar"));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(e.toString(), contains("Expected: Body: 'foobar'"));
        expect(e.toString(), contains("Body: text"));
      }
    });

    test("Can match JSON Object", () async {
      var defaultTestClient = new TestClient.onPort(4000);

      server.queueResponse(
          new Response.ok({"foo": "bar"})..contentType = ContentType.JSON);
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody(isNotNull));

      server.queueResponse(
          new Response.ok({"foo": "bar"})..contentType = ContentType.JSON);
      response = await defaultTestClient.request("/foo").get();
      try {
        expect(response, hasBody({"foo": "notbar"}));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(e.toString(), contains("Expected: Body: {'foo': 'notbar'}"));
        expect(e.toString(), contains('Body: {"foo":"bar"}'));
      }

      server.queueResponse(
          new Response.ok({"nocontenttype": "thatsaysthisisjson"})
            ..contentType = ContentType.TEXT);

      response = await defaultTestClient.request("/foo").get();
      try {
        expect(response,
            hasBody(containsPair("nocontenttype", "thatsaysthisisjson")));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(
            e.toString(),
            contains(
                "Expected: Body: contains pair 'nocontenttype' => 'thatsaysthisisjson'"));
        expect(e.toString(),
            contains("Body: {nocontenttype: thatsaysthisisjson}"));
      }
    });
  });

  group("Body, value matchers", () {
    MockHTTPServer server = new MockHTTPServer(4000);
    setUpAll(() async {
      await server.open();
    });

    tearDownAll(() async {
      await server?.close();
    });

    test("List of terms", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok([1, 2, 3]));
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody([1, 2, 3]));

      expect(response, hasBody(everyElement(greaterThan(0))));

      try {
        expect(response, hasBody([1, 2]));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(e.toString(), contains("Expected: Body: [1, 2]"));
        expect(e.toString(), contains("Body: [1,2,3]"));
      }

      try {
        expect(response, hasBody(everyElement(lessThan(0))));

        expect(true, false);
      } on TestFailure catch (e) {
        expect(e.toString(),
            contains("Expected: Body: every element(a value less than <0>)"));
        expect(e.toString(), contains("Body: [1,2,3]"));
      }
    });

    test("Exact map", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok({"foo": "bar", "x": "y"}));
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody({"foo": "bar", "x": "y"}));

      try {
        expect(response, hasBody({"foo": "notbar", "x": "y"}));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(e.toString(),
            contains("Expected: Body: {'foo': 'notbar', 'x': 'y'}"));
        expect(e.toString(), contains('Body: {"foo":"bar","x":"y"}'));
      }
    });

    test("Map with matchers", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok({"foo": "bar", "x": 5}));
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody({"foo": isString, "x": greaterThan(0)}));

      expect(response, hasBody({"foo": isString, "x": 5}));

      try {
        expect(response, hasBody({"foo": isNot(isString), "x": 5}));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(
            e.toString(),
            contains(
                "Expected: Body: {'foo': <not an instance of String>, 'x': 5}"));
        expect(e.toString(), contains('Body: {"foo":"bar","x":5}'));
      }
    });

    test("Partial match, one level", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok({"foo": "bar", "x": 5}));
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody(partial({"foo": "bar"})));
      expect(response, hasBody(partial({"x": greaterThan(0)})));

      try {
        expect(response, hasBody(partial({"foo": "notbar"})));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(e.toString(),
            contains("Expected: Body: Partially matches: {foo: 'notbar',}"));
        expect(e.toString(), contains('Body: {"foo":"bar","x":5}'));
      }
      try {
        expect(response, hasBody(partial({"x": lessThan(0)})));
        expect(true, false);
      } on TestFailure catch (e) {
        expect(
            e.toString(),
            contains(
                "Expected: Body: Partially matches: {x: a value less than <0>,}"));
        expect(e.toString(), contains('Body: {"foo":"bar","x":5}'));
      }
    });
  });

  group("Total matcher", () {
    MockHTTPServer server = new MockHTTPServer(4000);
    setUpAll(() async {
      await server.open();
    });

    tearDownAll(() async {
      await server?.close();
    });

    test("Omit status code ignores it", () async {
      var defaultTestClient = new TestClient.onPort(4000);

      server.queueResponse(
          new Response.ok({"foo": "bar"})..contentType = ContentType.JSON);

      var response = await defaultTestClient.request("/foo").get();
      expect(
          response,
          hasResponse(null, {"foo": "bar"},
              headers: {"content-type": "application/json; charset=utf-8"}));
    });

    test("Omit headers ignores them", () async {
      var defaultTestClient = new TestClient.onPort(4000);

      server.queueResponse(new Response.ok({"foo": "bar"},
          headers: {"content-type": "application/json; charset=utf-8"}));
      var response = await defaultTestClient.request("/foo").get();

      expect(response, hasResponse(200, {"foo": "bar"}));
    });

    test("Omit body ignores them", () async {
      var defaultTestClient = new TestClient.onPort(4000);

      server.queueResponse(new Response.ok({"foo": "bar"},
          headers: {"content-type": "application/json"}));
      var response = await defaultTestClient.request("/foo").get();
      expect(
          response,
          hasResponse(null, null,
              headers: {"Content-Type": "application/json; charset=utf-8"}));
    });
  });
}
