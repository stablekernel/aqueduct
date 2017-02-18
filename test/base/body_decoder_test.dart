import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  group("Default decoders", () {
    HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test("application/json decoder works on valid json", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/json"},
              body: JSON.encode({"a": "val"}))
          .catchError((err) => null);
      var request = await server.first;

      var body = await HTTPBody.decode(request);
      expect(body, {"a": "val"});
    });

    test("application/x-form-url-encoded decoder works on valid form",
        () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/x-www-form-urlencoded"},
              body: "a=b&c=2")
          .catchError((err) => null);
      var request = await server.first;

      var body = await HTTPBody.decode(request);
      expect(body, {
        "a": ["b"],
        "c": ["2"]
      });
    });

    test("Any text decoder works on text", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "text/plain"}, body: "foobar")
          .catchError((err) => null);

      var request = await server.first;

      var body = await HTTPBody.decode(request);
      expect(body, "foobar");
    });

    test("No found decoder for primary type returns binary", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "notarealthing/nothing"},
              body: "foobar")
          .catchError((err) => null);
      ;
      var request = await server.first;

      var body = await HTTPBody.decode(request);
      expect(body, "foobar".codeUnits);
    });

    test("No content-type returns binary", () async {
      var req = await new HttpClient()
          .openUrl("POST", Uri.parse("http://localhost:8123"));
      req.add("foobar".codeUnits);
      req.close().catchError((err) => null);

      var request = await server.first;

      expect(request.headers.contentType, isNull);

      var body = await HTTPBody.decode(request);
      expect(body, "foobar".codeUnits);
    });

    test("Decoder that matches primary type but not subtype fails", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/notarealthing"},
              body: "a=b&c=2")
          .catchError((err) => null);
      var request = await server.first;

      try {
        var _ = await HTTPBody.decode(request);
      } on HTTPBodyDecoderException catch (e) {
        expect(e, isNotNull);
      }
    });

    test("Failed decoding throws exception", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "application/json"}, body: "{a=b&c=2")
          .catchError((err) => null);
      var request = await server.first;

      try {
        var _ = await HTTPBody.decode(request);
      } on HTTPBodyDecoderException catch (e) {
        expect(e, isNotNull);
        expect(e.underlyingException is FormatException, true);
      }
    });
  });

  group("Non-default decoders", () {
    HttpServer server;

    setUpAll(() {
      HTTPBody.addDecoder(new ContentType("application", "thingy"),
          (req) async {
        return "application/thingy";
      });
      HTTPBody.addDecoder(new ContentType("somethingelse", "*"),
          (req) async {
        return "somethingelse/*";
      });
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
              body: "this doesn't matter")
          .catchError((err) => null);
      var request = await server.first;

      var body = await HTTPBody.decode(request);
      expect(body, "application/thingy");
    });

    test("Added decoder that matches any subtype works", () async {
      http
          .post("http://localhost:8123",
              headers: {"Content-Type": "somethingelse/whatever"},
              body: "this doesn't matter")
          .catchError((err) => null);
      ;
      var request = await server.first;

      var body = await HTTPBody.decode(request);
      expect(body, "somethingelse/*");
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
      var body = new HTTPBody(await server.first);
      expect(await body.decodeAsMap(), {"a": "val"});
    });

    test("Return valid asMap from already decoded body", () async {
      postJSON({"a" : "val"});
      var body = new HTTPBody(await server.first);
      await body.decodedData;
      expect(body.asMap(), {"a": "val"});
    });

    test("Call asMap prior to decode throws exception", () async {
      postJSON({"a" : "val"});
      var body = new HTTPBody(await server.first);

      try {
        body.asMap();
        expect(true, false);
      } on HTTPBodyDecoderException {}
    });

    test("decodeAsMap with non-map returns HTTPBodyException", () async {
      postJSON("a");
      var body = new HTTPBody(await server.first);

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
      var body = new HTTPBody(await server.first);

      expect(await body.decodeAsMap(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asMap with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/json"})
          .catchError((err) => null);

      var body = new HTTPBody(await server.first);
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
      var body = new HTTPBody(await server.first);
      expect(await body.decodeAsList(), [{"a": "val"}]);
    });

    test("Return valid asList from already decoded body", () async {
      postJSON([{"a" : "val"}]);
      var body = new HTTPBody(await server.first);
      await body.decodedData;
      expect(body.asList(), [{"a": "val"}]);
    });

    test("Call asList prior to decode throws exception", () async {
      postJSON([{"a" : "val"}]);
      var body = new HTTPBody(await server.first);

      try {
        body.asList();
        expect(true, false);
      } on HTTPBodyDecoderException {}
    });

    test("decodeAsList with non-list returns HTTPBodyException", () async {
      postJSON("a");
      var body = new HTTPBody(await server.first);

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
      var body = new HTTPBody(await server.first);

      expect(await body.decodeAsList(), null);
      expect(body.hasBeenDecoded, true);
    });

    test("asList with no data returns null", () async {
      http
          .post("http://localhost:8123",
          headers: {"Content-Type": "application/json"})
          .catchError((err) => null);

      var body = new HTTPBody(await server.first);
      await body.decodedData;
      expect(body.asList(), null);
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
  });
}

Future postJSON(dynamic json) {
  return http
      .post("http://localhost:8123",
        headers: {"Content-Type": "application/json"},
        body: JSON.encode(json))
      .catchError((err) => null);
}