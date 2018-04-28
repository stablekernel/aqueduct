import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';

void main() {
  group("Matcher Basics", () {
    MockHTTPServer server = new MockHTTPServer(4000);
    setUpAll(() async {
      await server.open();
      server.defaultResponse = new Response.ok(null);
    });

    tearDownAll(() async {
      await server.close();
    });

    test("Response matcher not using response gives appropriate error", () {
      expectFailureFor(() {
        expect("foo", hasStatus(200));
      }, allOf([
        contains("Expected:"),
        contains("Status code must be 200"),
        contains("Actual: 'foo'"),
        contains(
            "Which: Is not an instance of TestResponse")
      ]));
    });

    test("Status code matcher succeeds when correct", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasStatus(200));
    });

    test("Status code matcher fails with useful message when wrong", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();

      expectFailureFor(() {
        expect(response, hasStatus(400));
      }, allOf([
        contains("Headers can be anything"),
        contains("Body can be anything"),
        contains("Status codes are different. Expected: 400. Actual: 200")
      ]));
    });
  });

  group("Header matchers", () {
    final DateTime xTimestamp = DateTime.parse("1984-08-04T00:00:00Z");

    HttpServer server;
    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4000);
      server.listen((req) {
        req.response.statusCode = 200;

        if (req.uri.query.contains("timestamp")) {
          req.response.headers.add("x-timestamp", xTimestamp.toIso8601String());
        } else if (req.uri.query.contains("date")) {
          req.response.headers.add("x-date", HttpDate.format(xTimestamp));
        }

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

      expectFailureFor(() {
        expect(response, hasHeaders({"invalid": isNotNull}));
      }, allOf([
        contains("header 'invalid' must be not null"),
        contains("Status code is 200"),
        contains("x-frame-options")
      ]));
    });

    test("Ensure values of some headers w/ matcher", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(
          response,
          hasHeaders({
            "x-frame-options": "SAMEORIGIN",
            "content-length": lessThan(1)
          }));

      expectFailureFor(() {
        expect(response, hasHeaders({"x-frame-options": startsWith("foobar")}));
      }, allOf([
        contains("x-frame-options: SAMEORIGIN"),
        contains(
              "header 'x-frame-options' must be a string starting with 'foobar'"),
        contains("Which: the following headers differ: 'x-frame-options'")
      ]));
    });

    test("Ensure non-existence of header", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasHeaders({"invalid": isNotPresent}));

      expectFailureFor(() {
        expect(response, hasHeaders({"x-frame-options": isNotPresent}));
      }, allOf([
        contains("'x-frame-options' must be non-existent"),
        contains("x-frame-options: SAMEORIGIN"),
        contains(
            "Which: the following headers differ: 'x-frame-options'")
      ]));
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
            "content-length": greaterThan(-1)
          }, failIfContainsUnmatchedHeader: true));

      expectFailureFor(() {
        expect(
            response,
            hasHeaders({"x-frame-options": isNotNull},
                failIfContainsUnmatchedHeader: true));
      }, allOf([
        contains("actual has extra headers")
      ]));
    });

    test("DateTime isBefore,isAfter, etc.", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo?timestamp").get();
      expect(response, hasHeaders({"x-timestamp": isAfter(xTimestamp.subtract(new Duration(seconds: 10)))}));
      expect(response, hasHeaders({"x-timestamp": isBefore(xTimestamp.add(new Duration(seconds: 10)))}));
      expect(response, hasHeaders({"x-timestamp": isBeforeOrSameMomentAs(xTimestamp)}));
      expect(response, hasHeaders({"x-timestamp": isBeforeOrSameMomentAs(xTimestamp.add(new Duration(seconds: 10)))}));
      expect(response, hasHeaders({"x-timestamp": isAfterOrSameMomentAs(xTimestamp)}));
      expect(response, hasHeaders({"x-timestamp": isAfterOrSameMomentAs(xTimestamp.subtract(new Duration(seconds: 10)))}));
      expect(response, hasHeaders({"x-timestamp": isSameMomentAs(xTimestamp)}));

      expectFailureFor(() {
        expect(response, hasHeaders({"x-timestamp": isAfter(xTimestamp.add(new Duration(seconds: 10)))}));
      }, allOf([
        contains("must be after ${xTimestamp.add(new Duration(seconds: 10)).toIso8601String()}")
      ]));

      expectFailureFor(() {
        expect(response, hasHeaders({"x-timestamp": isBefore(xTimestamp.subtract(new Duration(seconds: 10)))}));
      }, allOf([
        contains("must be before ${xTimestamp.subtract(new Duration(seconds: 10)).toIso8601String()}")
      ]));

      expectFailureFor(() {
        expect(response, hasHeaders({"x-timestamp": isBeforeOrSameMomentAs(xTimestamp.subtract(new Duration(seconds: 10)))}));
      }, allOf([
        contains("must be before or same moment as ${xTimestamp.subtract(new Duration(seconds: 10)).toIso8601String()}")
      ]));

      expectFailureFor(() {
        expect(response, hasHeaders({"x-timestamp": isAfterOrSameMomentAs(xTimestamp.add(new Duration(seconds: 10)))}));
      }, allOf([
        contains("must be after or same moment as ${xTimestamp.add(new Duration(seconds: 10)).toIso8601String()}")
      ]));

      expectFailureFor(() {
        expect(response, hasHeaders({"x-timestamp": isSameMomentAs(xTimestamp.add(new Duration(seconds: 10)))}));
      }, allOf([
        contains("must be same moment as ${xTimestamp.add(new Duration(seconds: 10)).toIso8601String()}")
      ]));
    });

    test("HttpDate", () async {
      // Don't need to test variants of HttpDate, only that it gets parsed correctly
      var defaultTestClient = new TestClient.onPort(4000);
      var response = await defaultTestClient.request("/foo?date").get();

      expect(response, hasHeaders({"x-date": isSameMomentAs(xTimestamp)}));
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

      expectFailureFor(() {
        expect(response, hasBody(isNotNull));
      }, contains("the body differs"));
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
      expectFailureFor(() {
        expect(response, hasBody("foobar"));
      }, allOf([
        contains("Expected: foobar"),
        contains("Actual: text")
      ]));
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
      expectFailureFor(() {
        expect(response, hasBody({"foo": "notbar"}));
      }, allOf([
        contains("Body after decoding"),
        contains("{'foo': 'notbar'}"),
        contains("body differs for the following reasons"),
        contains("was 'bar' instead of 'notbar' at location ['foo']"),
      ]));
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

      expectFailureFor(() {
        expect(response, hasBody([1, 2]));
      }, allOf([
        contains("[1, 2]"),
        contains("longer than expected at location [2]")
      ]));

      expectFailureFor(() {
        expect(response, hasBody(everyElement(lessThan(0))));
      }, allOf([
        contains("every element(a value less than <0>)"),
        contains("has value <1> which is not a value less than <0> at index 0")
      ]));
    });

    test("Exact map", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok({"foo": "bar", "x": "y"}));
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody({"foo": "bar", "x": "y"}));

      expectFailureFor(() {
        expect(response, hasBody({"foo": "notbar", "x": "y"}));
      }, allOf([
        contains("{'foo': 'notbar', 'x': 'y'}"),
        contains("was 'bar' instead of 'notbar'")
      ]));
    });

    test("Map with matchers", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok({"foo": "bar", "x": 5}));
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody({"foo": isString, "x": greaterThan(0)}));

      expect(response, hasBody({"foo": isString, "x": 5}));

      expectFailureFor(() {
        expect(response, hasBody({"foo": isNot(isString), "x": 5}));
      }, allOf([
        contains("{'foo': <not an instance of String>, 'x': 5}"),
        contains('does not match not an instance of String at location')
      ]));
    });

    test("Partial match, one level", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok({"foo": "bar", "x": 5}));
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody(partial({"foo": "bar"})));
      expect(response, hasBody(partial({"x": greaterThan(0)})));

      expectFailureFor(() {
        expect(response, hasBody(partial({"foo": "notbar"})));
      }, allOf([
        contains("a map that contains at least the following"),
      ]));

      expectFailureFor(() {
        expect(response, hasBody(partial({"x": lessThan(0)})));
      }, allOf([
        contains("'x' is not a value less than <0>"),
      ]));
    });

    test("Partial match, null and not present", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok({"foo": null, "bar": "boo"}));
      var response = await defaultTestClient.request("/foo").get();
      expect(response, hasBody(partial({"bar": "boo"})));
      expect(response, hasBody(partial({"foo": isNull})));
      expect(response, hasBody(partial({"baz": isNotPresent})));

      expectFailureFor(() {
        expect(response, hasBody(partial({"foo": isNotPresent})));
      }, allOf([
        contains("key 'foo' must be non-existent"),
        contains("following keys differ")
      ]));

      expectFailureFor(() {
        expect(response, hasBody(partial({"bar": isNotPresent})));
      }, allOf([
        contains("key 'bar' must be non-existent"),
        contains('following keys differ')
      ]));
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

    test("Succeeds on fully specificed spec", () async {
      var defaultTestClient = new TestClient.onPort(4000);
      server.queueResponse(new Response.ok({"a": "b"})..contentType = ContentType.JSON);
      var resp = expectResponse(await defaultTestClient.request("/foo").get(),
          200, body: {
            "a": "b"
          }, headers: {
            "content-type": ContentType.JSON
          });

      expect(resp.statusCode, 200);
    });

    test("Omit status code from matcher, matching ignores it", () async {
      var defaultTestClient = new TestClient.onPort(4000);

      server.queueResponse(
          new Response.ok({"foo": "bar"})..contentType = ContentType.JSON);

      var response = await defaultTestClient.request("/foo").get();
      expect(
          response,
          hasResponse(null, body: {"foo": "bar"},
              headers: {"content-type": "application/json; charset=utf-8"}));
    });

    test("Omit headers from matcher, matching ignores them", () async {
      var defaultTestClient = new TestClient.onPort(4000);

      server.queueResponse(new Response.ok({"foo": "bar"},
          headers: {"content-type": "application/json; charset=utf-8"}));
      var response = await defaultTestClient.request("/foo").get();

      expect(response, hasResponse(200, body: {"foo": "bar"}));
    });

    test("Omit body ignores them", () async {
      var defaultTestClient = new TestClient.onPort(4000);

      server.queueResponse(
          new Response.ok({"foo": "bar"})..contentType = ContentType.JSON);
      var response = await defaultTestClient.request("/foo").get();
      expect(
          response,
          hasResponse(null, body: null,
              headers: {"Content-Type": "application/json; charset=utf-8"}));
    });
  });
}

TestFailure failureFor(void f()) {
  try {
    f();
  } on TestFailure catch (e) {
    return e;
  }

  throw new TestFailure("failureFor succeeded, must not succeed.");
}

void expectFailureFor(void f(), dynamic matcher) {
  var msg = failureFor(f).toString();
  expect(msg, matcher);
}