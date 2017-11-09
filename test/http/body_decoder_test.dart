import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  var defaultSize = HTTPRequestBody.maxSize;
  setUp(() {
    // Revert back to default before each test
    HTTPRequestBody.maxSize = defaultSize;
  });

  group("Default decoders", () {
    HttpServer server;
    Request request;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      await request?.raw?.response?.close();
      await server?.close(force: true);
    });

    group("Content vs. empty", () {
      HttpClient client;
      setUp(() {
        client = new HttpClient();
      });

      tearDown(() {
        client.close(force: true);
      });

      test("Empty body shows as isEmpty", () async {
        http.get("http://localhost:8123").catchError((err) => null);
        var request = await server.first;
        var body = new HTTPRequestBody(request);
        expect(body.isEmpty, true);
      });

      test("Request with content-length header shows is not empty", () async {
        var json = UTF8.encode(JSON.encode({"k": "v"}));
        var req = await client.openUrl("POST", Uri.parse("http://localhost:8123"));
        req.headers.add(HttpHeaders.CONTENT_TYPE, ContentType.JSON.toString());
        req.headers.add(HttpHeaders.CONTENT_LENGTH, json.length);
        req.add(json);
        var f = req.close();

        var request = await server.first;
        expect(request.headers.value(HttpHeaders.CONTENT_LENGTH), "${json.length}");
        var body = new HTTPRequestBody(request);
        expect(body.isEmpty, false);

        request.response.close();
        await f;
      });

      test("Request with chunked transfer encoding shows not empty", () async {
        var json = UTF8.encode(JSON.encode({"k": "v"}));
        var req = await client.openUrl("POST", Uri.parse("http://localhost:8123"));
        req.headers.add(HttpHeaders.CONTENT_TYPE, ContentType.JSON.toString());
        req.add(json);
        var f = req.close();

        var request = await server.first;
        expect(request.headers.value(HttpHeaders.CONTENT_LENGTH), isNull);
        expect(request.headers.value(HttpHeaders.TRANSFER_ENCODING), "chunked");
        var body = new HTTPRequestBody(request);
        expect(body.isEmpty, false);

        request.response.close();
        await f;
      });
    });

    test("application/json decoder works on valid json", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/json"},
              body: JSON.encode({"a": "val"}))
          .catchError((err) => null);

      request = new Request(await server.first);
      var body = await request.body.decodedData;
      expect(body, [{"a": "val"}]);
    });

    test("Omit charset from known decoder defaults to charset added if exists", () async {
      var client = new HttpClient();
      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.CONTENT_TYPE, "application/json");
      req.add(UTF8.encode(JSON.encode({"a": "val"})));
      req.close().catchError((err) => null);

      request = new Request(await server.first);
      expect(request.raw.headers.contentType.charset, null);

      var body = await request.body.decodedData;
      expect(body, [{"a": "val"}]);
    });

    test("application/x-form-url-encoded decoder works on valid form data",
        () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/x-www-form-urlencoded"},
              body: "a=b&c=2%2F4")
          .catchError((err) => null);
      var request = new Request(await server.first);
      request.body.retainOriginalBytes = true;
      var body = await request.body.decodedData;
      expect(body, [{
        "a": ["b"],
        "c": ["2/4"]
      }]);

      expect(UTF8.decode(request.body.asBytes()), "a=b&c=2%2F4");
    });

    test("Any text decoder works on text with charset", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "text/plain; charset=utf-8"}, body: "foobar")
          .catchError((err) => null);

      var request = new Request(await server.first);
      var body = await request.body.decodedData;
      expect(body.fold("", (p, v) => p + v), "foobar");
    });

    test("No found decoder for primary type returns binary", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "notarealthing/nothing"},
              body: "foobar".codeUnits)
          .catchError((err) => null);

      var request = new Request(await server.first);
      var body = await request.body.decodedData;
      expect(body, "foobar".codeUnits);
    });

    test("No content-type returns binary", () async {
      var req = await new HttpClient()
          .openUrl("POST", Uri.parse("http://localhost:8123"));
      req.add("foobar".codeUnits);
      req.close().catchError((err) => null);

      var request = new Request(await server.first);
      var body = await request.body.decodedData;

      expect(request.raw.headers.contentType, isNull);
      expect(body, "foobar".codeUnits);
    });

    test("Failed decoding throws exception", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/json"}, body: "{a=b&c=2")
          .catchError((err) => null);
      var request = new Request(await server.first);

      try {
        await request.body.decodedData;
        expect(true, false);
      } on HTTPBodyDecoderException catch (e) {
        expect(e.underlyingException is FormatException, true);
      }
    });
  });

  group("Non-default decoders", () {
    HttpServer server;

    setUpAll(() {
      // We'll just use JSON here so we don't have to write a separate codec
      // to test whether or not this content-type gets paired to a codec.
      HTTPCodecRepository.defaultInstance.add(new ContentType("application", "thingy"), const JsonCodec());
      HTTPCodecRepository.defaultInstance.add(new ContentType("somethingelse", "*", charset: "utf-8"), const JsonCodec());
    });

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Added decoder works when content-type matches", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/thingy"},
              body: JSON.encode({"key":"value"}))
          .catchError((err) => null);
      var request = new Request(await server.first);
      var body = await request.body.decodedData;
      expect(body, [{"key":"value"}]);
    });

    test("Added decoder that matches any subtype works", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "somethingelse/whatever"},
              body: JSON.encode({"key":"value"}))
          .catchError((err) => null);

      var request = new Request(await server.first);
      var body = await request.body.decodedData;
      expect(body, [{"key":"value"}]);
    });

    test("Omit charset from added decoder with default charset and match-all subtype", () async {
      var client = new HttpClient();
      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.CONTENT_TYPE, "somethingelse/foobar");
      req.add(UTF8.encode(JSON.encode({"a": "val"})));
      req.close().catchError((err) => null);

      var request = new Request(await server.first);
      expect(request.raw.headers.contentType.charset, null);

      var body = await request.body.decodedData;
      expect(body, [{"a": "val"}]);
    });

    test("Omit charset from added decoder does not add charset decoded if not specified", () async {
      var client = new HttpClient();
      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.CONTENT_TYPE, "application/thingy");
      req.add(UTF8.encode(JSON.encode({"a": "val"})));
      req.close().catchError((err) => null);

      var request = new Request(await server.first);
      expect(request.raw.headers.contentType.charset, null);

      // The test fails for a different reason in checked vs. unchecked mode.
      // Tests run in checked mode, but coverage runs in unchecked mode.
      var data;
      try {
        data = await request.body.decodedData;
      } catch (e) {
        expect(e, isNotNull);
      }

      expect(data, isNull);
    });
  });

  group("Casting methods - map", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Decode valid decodeAsMap", () async {
      postJSON({"a" : "val"});
      var body = new HTTPRequestBody(await server.first);
      expect(await body.decodeAsMap(), {"a": "val"});
    });

    test("Return valid asMap from already decoded body", () async {
      postJSON({"a" : "val"});
      var body = new HTTPRequestBody(await server.first);
      await body.decodedData;
      expect(body.asMap(), {"a": "val"});
    });

    test("Call asMap prior to decode throws exception", () async {
      postJSON({"a" : "val"});
      var body = new HTTPRequestBody(await server.first);

      try {
        body.asMap();
        expect(true, false);
      } on HTTPBodyDecoderException {}
    });

    test("decodeAsMap with non-map returns HTTPBodyException", () async {
      postJSON("a");
      var body = new HTTPRequestBody(await server.first);

      try {
        await body.decodeAsMap();
        expect(true, false);
      } on HTTPBodyDecoderException {}
    });

    test("decodeAsMap with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/json"})
          .catchError((err) => null);
      var body = new HTTPRequestBody(await server.first);

      expect(await body.decodeAsMap(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asMap with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/json"})
          .catchError((err) => null);

      var body = new HTTPRequestBody(await server.first);
      await body.decodedData;
      expect(body.asMap(), null);
    });
  });

  group("Casting methods - list", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Decode valid decodeAsList", () async {
      postJSON([{"a": "val"}]);
      var body = new HTTPRequestBody(await server.first);
      expect(await body.decodeAsList(), [{"a": "val"}]);
    });

    test("Return valid asList from already decoded body", () async {
      postJSON([{"a" : "val"}]);
      var body = new HTTPRequestBody(await server.first);
      await body.decodedData;
      expect(body.asList(), [{"a": "val"}]);
    });

    test("Call asList prior to decode throws exception", () async {
      postJSON([{"a" : "val"}]);
      var body = new HTTPRequestBody(await server.first);

      try {
        body.asList();
        expect(true, false);
      } on HTTPBodyDecoderException {}
    });

    test("decodeAsList with non-list returns HTTPBodyException", () async {
      postJSON("a");
      var body = new HTTPRequestBody(await server.first);

      try {
        await body.decodeAsList();
        expect(true, false);
      } on HTTPBodyDecoderException {}
    });

    test("decodeAsList with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/json"})
          .catchError((err) => null);
      var body = new HTTPRequestBody(await server.first);

      expect(await body.decodeAsList(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asList with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/json"})
          .catchError((err) => null);

      var body = new HTTPRequestBody(await server.first);
      await body.decodedData;
      expect(body.asList(), null);
    });
  });

  group("Casting methods - String", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Decode valid decodeAsString", () async {
      postString("abcdef");
      var body = new HTTPRequestBody(await server.first);
      expect(await body.decodeAsString(), "abcdef");
    });

    test("Decode large string", () async {
      var largeString = new List.generate(1024 * 1024,
              (c) => "${c % 10 + 48}".codeUnitAt(0)).join("");

      postString(largeString);
      var body = new HTTPRequestBody(await server.first);
      expect(await body.decodeAsString(), largeString);
    });

    test("Return valid asString from already decoded body", () async {
      postString("abcdef");
      var body = new HTTPRequestBody(await server.first);
      await body.decodedData;
      expect(body.asString(), "abcdef");
    });

    test("Call asString prior to decode throws exception", () async {
      postString("abcdef");
      var body = new HTTPRequestBody(await server.first);

      try {
        body.asString();
        expect(true, false);
      } on HTTPBodyDecoderException {}
    });

    test("Call asString with non-string data throws exception", () async {
      postJSON({"k": "v"});
      var body = new HTTPRequestBody(await server.first);

      try {
        await body.decodeAsString();
        expect(true, false);
      } on HTTPBodyDecoderException {}
    });

    test("decodeAsString with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "text/plain; charset=utf-8"})
          .catchError((err) => null);
      var body = new HTTPRequestBody(await server.first);

      expect(await body.decodeAsString(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asString with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "text/plain; charset=utf-8"})
          .catchError((err) => null);

      var body = new HTTPRequestBody(await server.first);
      await body.decodedData;
      expect(body.asString(), null);
    });
  });

  group("Casting methods - bytes", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Decode valid decodeAsBytes", () async {
      postBytes([1, 2, 3, 4]);
      var body = new HTTPRequestBody(await server.first);
      expect(await body.decodeAsBytes(), [1, 2, 3, 4]);
    });

    test("Return valid asBytes from already decoded body", () async {
      postBytes([1, 2, 3, 4]);
      var body = new HTTPRequestBody(await server.first);
      await body.decodedData;
      expect(body.asBytes(), [1, 2, 3, 4]);
    });

    test("Call asBytes prior to decode throws exception", () async {
      postBytes([1, 2, 3, 4]);

      var body = new HTTPRequestBody(await server.first);
      try {
        body.asBytes();
        expect(true, false);
      } on HTTPBodyDecoderException {}
    });

    test("decodeAsBytes with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/octet-stream"})
          .catchError((err) => null);
      var body = new HTTPRequestBody(await server.first);

      expect(await body.decodeAsBytes(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asBytes with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/octet-stream"})
          .catchError((err) => null);

      var body = new HTTPRequestBody(await server.first);
      await body.decodedData;
      expect(body.asBytes(), null);
    });

    test("Throw exception if not retaining bytes and body was decoded", () async {
      postJSON({"k": "v"});
      var body = new HTTPRequestBody(await server.first);
      try {
        await body.decodeAsBytes();
        expect(true, false);
      } on HTTPBodyDecoderException catch (e) {
        expect(e.message, contains("expected list of bytes"));
      }
    });

    test("Retain bytes when codec is used", () async {
      postJSON({"k": "v"});

      var body = new HTTPRequestBody(await server.first)..retainOriginalBytes = true;
      await body.decodedData;
      expect(body.asMap(), {"k": "v"});
      expect(body.asBytes(), UTF8.encode(JSON.encode({"k":"v"})));
    });

    test("Retain bytes when no codec is used", () async {
      postBytes([1, 2, 3, 4]);

      var body = new HTTPRequestBody(await server.first)..retainOriginalBytes = true;
      await body.decodedData;
      expect(body.asBytes(), [1, 2, 3, 4]);
    });
  });

  group("Request decoding behavior", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Subsequent decodes do not re-process body", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/json"},
              body: JSON.encode({"a": "val"}))
          .catchError((err) => null);

      var request = new Request(await server.first);

      var b1 = await request.body.decodedData;
      var b2 = await request.body.decodedData;

      expect(b1, isNotNull);
      expect(identical(b1, b2), true);
    });

    test("Failed decoding yields 500 from Controller", () async {
      HTTPCodecRepository.defaultInstance.add(new ContentType("application", "crasher"), new CrashingCodec());
      // If body decoding fails, we need to return 500 but also ensure we have closed the request
      // body stream
      server.map((req) => new Request(req)).listen((req) async {
        var next = new Controller();
        next.listen((req) async {
          // This'll crash
          var _ = await req.body.decodedData;

          return new Response.ok(200);
        });
        await next.receive(req);
      });

      var result = await http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/crasher"},
          body: JSON.encode({"key": "value"}));
      expect(result.statusCode, 500);

      // Send it again just to make sure things have recovered.
      result = await http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/crasher"},
          body: JSON.encode({"key": "value"}));
      expect(result.statusCode, 500);
    });
  });

  group("Form codec", () {
    test("Convert list of bytes with form codec", () {
      var codec = HTTPCodecRepository.defaultInstance.codecForContentType(new ContentType("application", "x-www-form-urlencoded"));
      var bytes = UTF8.encode("a=b&c=d");

      expect(codec.decode(bytes), {"a": ["b"], "c": ["d"]});
    });
  });

  group("Entity too large", () {
    HttpServer server;
    HttpClient client;

    setUp(() async {
      client = new HttpClient();
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      client.close(force: true);
      await server?.close(force: true);
    });

    test("Entity with known content-type that is too large is rejected, specified length", () async {
      HTTPRequestBody.maxSize = 8193;

      var controller = new Controller()
        ..listen((req) async {
          var body = await req.body.decodeAsMap();
          return new Response.ok(body);
        });
      server.listen((req) {
        controller.receive(new Request(req));
      });

      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.CONTENT_TYPE, "application/json; charset=utf-8");
      var body = {
        "key": new List.generate(8192 * 50, (_) => "a").join(" ")
      };
      var bytes = UTF8.encode(JSON.encode(body));
      req.headers.add(HttpHeaders.CONTENT_LENGTH, bytes.length);
      req.add(bytes);

      var response = await req.close().catchError((err) => null);
      expect(response.statusCode, 413);

      req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.CONTENT_TYPE, "application/json; charset=utf-8");
      body = {
        "key": "a"
      };
      req.add(UTF8.encode(JSON.encode(body)));
      response = await req.close();
      expect(JSON.decode(UTF8.decode(await response.first)), {"key": "a"});
    });

    test("Entity with unknown content-type that is too large is rejected, specified length", () async {
      HTTPRequestBody.maxSize = 8193;

      var controller = new Controller()
        ..listen((req) async {
          var body = await req.body.decodedData;
          return new Response.ok(body)..contentType = new ContentType("application", "octet-stream");
        });
      server.listen((req) {
        controller.receive(new Request(req));
      });

      var req = await client.postUrl(Uri.parse("http://localhost:8123"));
      var bytes = new List.generate(8192 * 100, (_) => 1);
      req.headers.add(HttpHeaders.CONTENT_TYPE, "application/octet-stream");
      req.headers.add(HttpHeaders.CONTENT_LENGTH, bytes.length);
      req.add(bytes);

      var response = await req.close().catchError((err) => null);
      expect(response.statusCode, 413);

      req = await client.postUrl(Uri.parse("http://localhost:8123"));
      req.headers.add(HttpHeaders.CONTENT_TYPE, "application/octet-stream");
      req.add([1, 2, 3, 4]);
      response = await req.close();
      expect(await response.toList(), [[1, 2, 3, 4]]);
    });
  });
}

Future postJSON(dynamic json) {
  return http
      .post("http://localhost:8123",
        headers: {"Content-Type": "application/json"},
        body: JSON.encode(json))
      .catchError((err) => null);
}

Future postString(String data) {
  return http
      .post("http://localhost:8123",
      headers: {"Content-Type": "text/html; charset=utf-8"},
      body: data)
      .catchError((err) => null);
}

Future postBytes(List<int> bytes) {
  return http
      .post("http://localhost:8123",
      headers: {"Content-Type": "application/octet-stream"},
      body: bytes)
      .catchError((err) => null);
}

class CrashingCodec extends Codec {
  @override
  Converter get encoder => const CrashingEncoder();
  @override
  Converter get decoder => null;
}

class CrashingEncoder extends Converter<String, List<int>> {
  const CrashingEncoder();
  @override
  List<int> convert(String object) => throw new Exception("uhoh");
}
