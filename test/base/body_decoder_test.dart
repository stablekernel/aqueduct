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
      await server?.close();
    });

    test("application/json decoder works on valid json", () async {
      http.post("http://localhost:8123", headers: {"Content-Type" : "application/json"}, body: JSON.encode({"a" : "val"}));
      var request = await server.first;

      var body = await HTTPBodyDecoder.decode(request);
      expect(body, {
        "a" : "val"
      });
    });

    test("application/x-form-url-encoded decoder works on valid form", () async {
      http.post("http://localhost:8123", headers: {"Content-Type" : "application/x-www-form-urlencoded"}, body: "a=b&c=2");
      var request = await server.first;

      var body = await HTTPBodyDecoder.decode(request);
      expect(body, {
        "a" : ["b"],
        "c" : ["2"]
      });
    });

    test("Any text decoder works on text", () async {
      http.post("http://localhost:8123", headers: {"Content-Type" : "text/plain"}, body: "foobar");
      var request = await server.first;

      var body = await HTTPBodyDecoder.decode(request);
      expect(body, "foobar");
    });

    test("No found decoder for primary type returns binary", () async {
      http.post("http://localhost:8123", headers: {"Content-Type" : "notarealthing/nothing"}, body: "foobar");
      var request = await server.first;

      var body = await HTTPBodyDecoder.decode(request);
      expect(body, "foobar".codeUnits);
    });

    test("No content-type returns binary", () async {
      var req = await new HttpClient().openUrl("POST", Uri.parse("http://localhost:8123"));
      req.add("foobar".codeUnits);
      req.close();
      var request = await server.first;

      expect(request.headers.contentType, isNull);

      var body = await HTTPBodyDecoder.decode(request);
      expect(body, "foobar".codeUnits);
    });

    test("Decoder that matches primary type but not subtype fails", () async {
      http.post("http://localhost:8123", headers: {"Content-Type" : "application/notarealthing"}, body: "a=b&c=2");
      var request = await server.first;

      try {
        var _ = await HTTPBodyDecoder.decode(request);
      } on HTTPBodyDecoderException catch (e) {
        expect(e, isNotNull);
      }
    });

    test("Failed decoding throws exception", () async {
      http.post("http://localhost:8123", headers: {"Content-Type" : "application/json"}, body: "{a=b&c=2");
      var request = await server.first;

      try {
        var _ = await HTTPBodyDecoder.decode(request);
      } on FormatException catch (e) {
        expect(e, isNotNull);
      }
    });
  });

  group("Non-default decoders", () {
    HttpServer server;

    setUpAll(() {
      HTTPBodyDecoder.addDecoder(new ContentType("application", "thingy"), (req) async {
        return "application/thingy";
      });
      HTTPBodyDecoder.addDecoder(new ContentType("somethingelse", "*"), (req) async {
        return "somethingelse/*";
      });
    });

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
    });

    tearDown(() async {
      await server?.close();
    });

    test("Added decoder works when content-type matches", () async {
      http.post("http://localhost:8123", headers: {"Content-Type" : "application/thingy"}, body: "this doesn't matter");
      var request = await server.first;

      var body = await HTTPBodyDecoder.decode(request);
      expect(body, "application/thingy");
    });

    test("Added decoder that matches any subtype works", () async {
      http.post("http://localhost:8123", headers: {"Content-Type" : "somethingelse/whatever"}, body: "this doesn't matter");
      var request = await server.first;

      var body = await HTTPBodyDecoder.decode(request);
      expect(body, "somethingelse/*");

    });
  });
}