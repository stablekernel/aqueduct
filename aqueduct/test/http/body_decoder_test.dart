import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  var defaultSize = RequestBody.maxSize;
  setUp(() {
    // Revert back to default before each test
    RequestBody.maxSize = defaultSize;
  });

  group("Default decoders", () {
    HttpServer server;
    Request request;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    });

    tearDown(() async {
      await request?.raw?.response?.close();
      await server?.close(force: true);
    });

    group("Content vs. empty", () {
      HttpClient client;
      setUp(() {
        client = HttpClient();
      });

      tearDown(() {
        client.close(force: true);
      });

      test("Empty body shows as isEmpty", () async {
        // ignore: unawaited_futures
        http.get("http://localhost:8123").catchError((err) => null);
        var request = await server.first;
        var body = RequestBody(request);
        expect(body.isEmpty, true);
      });

      test("Request with content-length header shows is not empty", () async {
        var bytes = utf8.encode(json.encode({"k": "v"}));
        var req = await client.openUrl("POST", Uri.parse("http://localhost:8123"));
        req.headers.add(HttpHeaders.contentTypeHeader, ContentType.json.toString());
        req.headers.add(HttpHeaders.contentLengthHeader, bytes.length);
        req.add(bytes);
        var f = req.close();

        var request = await server.first;
        expect(request.headers.value(HttpHeaders.contentLengthHeader), "${bytes.length}");
        var body = RequestBody(request);
        expect(body.isEmpty, false);

        // ignore: unawaited_futures
        request.response.close();
        await f;
      });

      test("Request with chunked transfer encoding shows not empty", () async {
        var bytes = utf8.encode(json.encode({"k": "v"}));
        var req = await client.openUrl("POST", Uri.parse("http://localhost:8123"));
        req.headers.add(HttpHeaders.contentTypeHeader, ContentType.json.toString());
        req.add(bytes);
        var f = req.close();

        var request = await server.first;
        expect(request.headers.value(HttpHeaders.contentLengthHeader), isNull);
        expect(request.headers.value(HttpHeaders.transferEncodingHeader), "chunked");
        var body = RequestBody(request);
        expect(body.isEmpty, false);

        // ignore: unawaited_futures
        request.response.close();
        await f;
      });
    });

    test("application/json decoder works on valid json", () async {
      // ignore: unawaited_futures
      http
          .post("http://localhost:8123", headers: {"Content-Type": "application/json"}, body: json.encode({"a": "val"}))
          .catchError((err) => null);

      request = Request(await server.first);
      Map<String, dynamic> body = await request.body.decode();
      expect(body, {"a": "val"});
    });

    test("Omit charset from known decoder defaults to charset added if exists", () async {
      var client = HttpClient();
      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.contentTypeHeader, "application/json");
      req.add(utf8.encode(json.encode({"a": "val"})));
      // ignore: unawaited_futures
      req.close().catchError((err) => null);

      request = Request(await server.first);
      expect(request.raw.headers.contentType.charset, null);

      Map<String, dynamic> body = await request.body.decode();
      expect(body, {"a": "val"});
    });

    test("application/x-form-url-encoded decoder works on valid form data", () async {
      // ignore: unawaited_futures
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: "a=b&c=2%2F4")
          .catchError((err) => null);
      var request = Request(await server.first);
      request.body.retainOriginalBytes = true;
      Map<String, dynamic> body = await request.body.decode();
      expect(body, {
        "a": ["b"],
        "c": ["2/4"]
      });

      expect(utf8.decode(request.body.originalBytes), "a=b&c=2%2F4");
    });

    test("Any text decoder works on text with charset", () async {
      // ignore: unawaited_futures
      http
          .post("http://localhost:8123", headers: {"Content-Type": "text/plain; charset=utf-8"}, body: "foobar")
          .catchError((err) => null);

      var request = Request(await server.first);
      String body = await request.body.decode();
      expect(body, "foobar");
    });

    test("No found decoder for primary type returns binary", () async {
      // ignore: unawaited_futures
      http
          .post("http://localhost:8123", headers: {"Content-Type": "notarealthing/nothing"}, body: "foobar".codeUnits)
          .catchError((err) => null);

      var request = Request(await server.first);
      List<int> body = await request.body.decode();
      expect(body, "foobar".codeUnits);
    });

    test("No content-type returns binary", () async {
      var req = await HttpClient().openUrl("POST", Uri.parse("http://localhost:8123"));
      req.add("foobar".codeUnits);
      // ignore: unawaited_futures
      req.close().catchError((err) => null);

      var request = Request(await server.first);
      List<int> body = await request.body.decode();

      expect(request.raw.headers.contentType, isNull);
      expect(body, "foobar".codeUnits);
    });

    test("Failed decoding throws exception", () async {
      // ignore: unawaited_futures
      http
          .post("http://localhost:8123", headers: {"Content-Type": "application/json"}, body: "{a=b&c=2")
          .catchError((err) => null);
      var request = Request(await server.first);

      try {
        await request.body.decode();
        expect(true, false);
      } on Response catch (e) {
        expect(e.statusCode, 400);
      }
    });
  });

  group("Non-default decoders", () {
    HttpServer server;

    setUpAll(() {
      // We'll just use JSON here so we don't have to write a separate codec
      // to test whether or not this content-type gets paired to a codec.
      CodecRegistry.defaultInstance.add(ContentType("application", "thingy"), const JsonCodec());
      CodecRegistry.defaultInstance.add(ContentType("somethingelse", "*", charset: "utf-8"), const JsonCodec());
    });

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Added decoder works when content-type matches", () async {
      // ignore: unawaited_futures
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/thingy"}, body: json.encode({"key": "value"}))
          .catchError((err) => null);
      var request = Request(await server.first);
      Map<String, dynamic> body = await request.body.decode();
      expect(body, {"key": "value"});
    });

    test("Added decoder that matches any subtype works", () async {
      // ignore: unawaited_futures
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "somethingelse/whatever"}, body: json.encode({"key": "value"}))
          .catchError((err) => null);

      var request = Request(await server.first);
      Map<String, dynamic> body = await request.body.decode();
      expect(body, {"key": "value"});
    });

    test("Omit charset from added decoder with default charset and match-all subtype", () async {
      var client = HttpClient();
      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.contentTypeHeader, "somethingelse/foobar");
      req.add(utf8.encode(json.encode({"a": "val"})));
      // ignore: unawaited_futures
      req.close().catchError((err) => null);

      var request = Request(await server.first);
      expect(request.raw.headers.contentType.charset, null);

      Map<String, dynamic> body = await request.body.decode();
      expect(body, {"a": "val"});
    });

    test("Omit charset from added decoder does not add charset decoded if not specified", () async {
      var client = HttpClient();
      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.contentTypeHeader, "application/thingy");
      req.add(utf8.encode(json.encode({"a": "val"})));
      // ignore: unawaited_futures
      req.close().catchError((err) => null);

      var request = Request(await server.first);
      expect(request.raw.headers.contentType.charset, null);

      // The test fails for a different reason in checked vs. unchecked mode.
      // Tests run in checked mode, but coverage runs in unchecked mode.
      dynamic data;
      try {
        data = await request.body.decode();
      } catch (e) {
        expect(e, isNotNull);
      }

      expect(data, isNull);
    });
  });

  group("Casting methods - map", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Decode valid decodeAsMap", () async {
      // ignore: unawaited_futures
      postJSON({"a": "val"});
      var body = RequestBody(await server.first);
      expect(await body.decode<Map<String, dynamic>>(), {"a": "val"});
    });

    test("Return valid asMap from already decoded body", () async {
      // ignore: unawaited_futures
      postJSON({"a": "val"});
      var body = RequestBody(await server.first);
      await body.decode();
      expect(body.as<Map<String, dynamic>>(), {"a": "val"});

      expect(body.as(), {"a": "val"});
    });

    test("Call asMap prior to decode throws error", () async {
      // ignore: unawaited_futures
      postJSON({"a": "val"});
      var body = RequestBody(await server.first);

      try {
        body.as<Map<String, dynamic>>();
        expect(true, false);
        // ignore: empty_catches
      } on StateError {}
    });

    test("decodeAsMap with non-map returns 400", () async {
      // ignore: unawaited_futures
      postJSON("a");
      var body = RequestBody(await server.first);

      try {
        await body.decode<Map<String, dynamic>>();
        expect(true, false);
      } on Response catch (e) {
        expect(e.statusCode, 400);
      }
    });

    test("decodeAsMap with no data returns null", () async {
      // ignore: unawaited_futures
      http.post("http://localhost:8123", headers: {"Content-Type": "application/json"}).catchError((err) => null);
      var body = RequestBody(await server.first);

      expect(await body.decode<Map<String, dynamic>>(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asMap with no data returns null", () async {
      // ignore: unawaited_futures
      http.post("http://localhost:8123", headers: {"Content-Type": "application/json"}).catchError((err) => null);

      var body = RequestBody(await server.first);
      await body.decode();
      expect(body.as<Map<String, dynamic>>(), null);
    });
  });

  group("Casting methods - list", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Decode valid decodeAsList", () async {
      // ignore: unawaited_futures
      postJSON([
        {"a": "val"}
      ]);
      var body = RequestBody(await server.first);
      expect(await body.decode<List<Map<String, dynamic>>>(), [
        {"a": "val"}
      ]);
    });

    test("Return valid asList from already decoded body", () async {
      // ignore: unawaited_futures
      postJSON([
        {"a": "val"}
      ]);
      var body = RequestBody(await server.first);
      await body.decode();
      expect(body.as<List<Map<String, dynamic>>>(), [
        {"a": "val"}
      ]);
    });

    test("Call asList prior to decode throws exception", () async {
      // ignore: unawaited_futures
      postJSON([
        {"a": "val"}
      ]);
      var body = RequestBody(await server.first);

      try {
        body.as<List<Map<String, dynamic>>>();
        expect(true, false);
        // ignore: empty_catches
      } on StateError {}
    });

    test("decodeAsList with non-list returns HTTPBodyException", () async {
      // ignore: unawaited_futures
      postJSON("a");
      var body = RequestBody(await server.first);

      try {
        await body.decode<List<Map<String, dynamic>>>();
        expect(true, false);
      } on Response catch (response) {
        expect(response.statusCode, 400);
      }
    });

    test("decodeAsList with no data returns null", () async {
      // ignore: unawaited_futures
      http.post("http://localhost:8123", headers: {"Content-Type": "application/json"}).catchError((err) => null);
      var body = RequestBody(await server.first);

      expect(await body.decode(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asList with no data returns null", () async {
      // ignore: unawaited_futures
      http.post("http://localhost:8123", headers: {"Content-Type": "application/json"}).catchError((err) => null);

      var body = RequestBody(await server.first);
      await body.decode();
      expect(body.as<List<Map<String, dynamic>>>(), null);
    });
  });

  group("Casting methods - String", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Decode valid decodeAsString", () async {
      // ignore: unawaited_futures
      postString("abcdef");
      var body = RequestBody(await server.first);
      expect(await body.decode<String>(), "abcdef");
    });

    test("Decode large string", () async {
      var largeString = List.generate(1024 * 1024, (c) => "${c % 10 + 48}".codeUnitAt(0)).join("");

      // ignore: unawaited_futures
      postString(largeString);
      var body = RequestBody(await server.first);
      expect(await body.decode<String>(), largeString);
    });

    test("Return valid asString from already decoded body", () async {
      // ignore: unawaited_futures
      postString("abcdef");
      var body = RequestBody(await server.first);
      await body.decode();
      expect(body.as<String>(), "abcdef");
    });

    test("Call asString prior to decode throws exception", () async {
      // ignore: unawaited_futures
      postString("abcdef");
      var body = RequestBody(await server.first);

      try {
        body.as<String>();
        expect(true, false);
        // ignore: empty_catches
      } on StateError {}
    });

    test("Call asString with non-string data throws exception", () async {
      // ignore: unawaited_futures
      postJSON({"k": "v"});
      var body = RequestBody(await server.first);

      try {
        await body.decode<String>();
        expect(true, false);
      } on Response catch (response) {
        expect(response.statusCode, 400);
      }
    });

    test("decodeAsString with no data returns null", () async {
      // ignore: unawaited_futures
      http.post("http://localhost:8123",
          headers: {"Content-Type": "text/plain; charset=utf-8"}).catchError((err) => null);
      var body = RequestBody(await server.first);

      expect(await body.decode<String>(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asString with no data returns null", () async {
      // ignore: unawaited_futures
      http.post("http://localhost:8123",
          headers: {"Content-Type": "text/plain; charset=utf-8"}).catchError((err) => null);

      var body = RequestBody(await server.first);
      await body.decode();
      expect(body.as<String>(), null);
    });
  });

  group("Casting methods - bytes", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Decode valid decodeAsBytes", () async {
      // ignore: unawaited_futures
      postBytes([1, 2, 3, 4]);
      var body = RequestBody(await server.first);
      expect(await body.decode<List<int>>(), [1, 2, 3, 4]);
    });

    test("Return valid asBytes from already decoded body", () async {
      // ignore: unawaited_futures
      postBytes([1, 2, 3, 4]);
      var body = RequestBody(await server.first);
      await body.decode();
      expect(body.as<List<int>>(), [1, 2, 3, 4]);
    });

    test("Call asBytes prior to decode throws error", () async {
      // ignore: unawaited_futures
      postBytes([1, 2, 3, 4]);

      var body = RequestBody(await server.first);
      try {
        body.as<List<int>>();
        expect(true, false);
        // ignore: empty_catches
      } on StateError {}
    });

    test("decodeAsBytes with no data returns null", () async {
      // ignore: unawaited_futures
      http.post("http://localhost:8123",
          headers: {"Content-Type": "application/octet-stream"}).catchError((err) => null);
      var body = RequestBody(await server.first);

      expect(await body.decode<List<int>>(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asBytes with no data returns null", () async {
      // ignore: unawaited_futures
      http.post("http://localhost:8123",
          headers: {"Content-Type": "application/octet-stream"}).catchError((err) => null);

      var body = RequestBody(await server.first);
      await body.decode();
      expect(body.as<List<int>>(), null);
    });

    test("Throw exception if not retaining bytes and body was decoded", () async {
      // ignore: unawaited_futures
      postJSON({"k": "v"});
      var body = RequestBody(await server.first);
      try {
        body.originalBytes;
        expect(true, false);
        // ignore: empty_catches
      } on StateError {}
    });

    test("Retain bytes when codec is used", () async {
      // ignore: unawaited_futures
      postJSON({"k": "v"});

      var body = RequestBody(await server.first)..retainOriginalBytes = true;
      await body.decode();
      expect(body.as<Map<String, dynamic>>(), {"k": "v"});
      expect(body.originalBytes, utf8.encode(json.encode({"k": "v"})));
    });

    test("Retain bytes when no codec is used", () async {
      // ignore: unawaited_futures
      postBytes([1, 2, 3, 4]);

      var body = RequestBody(await server.first)..retainOriginalBytes = true;
      await body.decode();
      expect(body.as<List<int>>(), [1, 2, 3, 4]);
    });
  });

  group("Request decoding behavior", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Subsequent decodes do not re-process body", () async {
      // ignore: unawaited_futures
      http
          .post("http://localhost:8123", headers: {"Content-Type": "application/json"}, body: json.encode({"a": "val"}))
          .catchError((err) => null);

      var request = Request(await server.first);

      var b1 = await request.body.decode();
      var b2 = await request.body.decode();

      expect(b1, isNotNull);
      expect(identical(b1, b2), true);
    });

    test("Failed decoding yields 500 from Controller", () async {
      // If body decoding fails, we need to return 500 but also ensure we have closed the request
      // body stream
      server.map((req) => Request(req)).listen((req) async {
        var next = PassthruController();
        next.linkFunction((req) async {
          // This'll crash
          var _ = await req.body.decode();

          return Response.ok(200);
        });
        await next.receive(req);
      });

      var result = await http.post("http://localhost:8123",
          headers: {"Content-Type": "application/json"}, body: utf8.encode('{"key":'));
      expect(result.statusCode, 400);

      // Send it again just to make sure things have recovered.
      result = await http.post("http://localhost:8123",
          headers: {"Content-Type": "application/json"}, body: utf8.encode('{"key":'));
      expect(result.statusCode, 400);
    });
  });

  group("Form codec", () {
    test("Convert list of bytes with form codec", () {
      var codec =
          CodecRegistry.defaultInstance.codecForContentType(ContentType("application", "x-www-form-urlencoded"));
      var bytes = utf8.encode("a=b&c=d");

      expect(codec.decode(bytes), {
        "a": ["b"],
        "c": ["d"]
      });
    });
  });

  group("Entity too large", () {
    HttpServer server;
    HttpClient client;

    setUp(() async {
      client = HttpClient();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    });

    tearDown(() async {
      client.close(force: true);
      await server?.close(force: true);
    });

    test("Entity with known content-type that is too large is rejected, specified length", () async {
      RequestBody.maxSize = 8193;

      var controller = PassthruController()
        ..linkFunction((req) async {
          var body = await req.body.decode<Map<String, dynamic>>();
          return Response.ok(body);
        });
      server.listen((req) {
        controller.receive(Request(req));
      });

      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.contentTypeHeader, "application/json; charset=utf-8");
      var body = {"key": List.generate(8192 * 50, (_) => "a").join(" ")};
      var bytes = utf8.encode(json.encode(body));
      req.headers.add(HttpHeaders.contentLengthHeader, bytes.length);
      req.add(bytes);

      var response = await req.close().catchError((err) => null);
      expect(response.statusCode, 413);

      req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.contentTypeHeader, "application/json; charset=utf-8");
      body = {"key": "a"};
      req.add(utf8.encode(json.encode(body)));
      response = await req.close();
      expect(json.decode(utf8.decode(await response.first)), {"key": "a"});
    });

    test("Entity with unknown content-type that is too large is rejected, specified length", () async {
      RequestBody.maxSize = 8193;

      var controller = PassthruController()
        ..linkFunction((req) async {
          var body = await req.body.decode();
          return Response.ok(body)..contentType = ContentType("application", "octet-stream");
        });
      server.listen((req) {
        controller.receive(Request(req));
      });

      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      var bytes = List.generate(8192 * 100, (_) => 1);
      req.headers.add(HttpHeaders.contentTypeHeader, "application/octet-stream");
      req.headers.add(HttpHeaders.contentLengthHeader, bytes.length);
      req.add(bytes);

      var response = await req.close().catchError((err) => null);
      expect(response.statusCode, 413);

      req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.contentTypeHeader, "application/octet-stream");
      req.add([1, 2, 3, 4]);
      response = await req.close();
      expect(await response.toList(), [
        [1, 2, 3, 4]
      ]);
    });
  });
}

Future postJSON(dynamic body) {
  return http
      .post("http://localhost:8123", headers: {"Content-Type": "application/json"}, body: json.encode(body))
      .catchError((err) => null);
}

Future postString(String data) {
  return http
      .post("http://localhost:8123", headers: {"Content-Type": "text/html; charset=utf-8"}, body: data)
      .catchError((err) => null);
}

Future postBytes(List<int> bytes) {
  return http
      .post("http://localhost:8123", headers: {"Content-Type": "application/octet-stream"}, body: bytes)
      .catchError((err) => null);
}
