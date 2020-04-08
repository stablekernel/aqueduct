import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  HttpServer server;
  HttpClient client;

  setUp(() async {
    client = HttpClient();
  });

  tearDown(() async {
    await server?.close();
    client.close(force: true);
  });

  test("Using an encoder that doesn't exist with a non-List<int> returns a 500",
      () async {
    var response = Response.ok("xyz")..contentType = ContentType("foo", "bar");
    server = await bindAndRespondWith(response);

    var resp = await http.get("http://localhost:8888");

    expect(resp.statusCode, 500);
    expect(response.headers["content-type"], isNull);
    expect(resp.body.isEmpty, true);
  });

  test("Using an encoder that doesn't exist with a List<int> is OK", () async {
    var response = Response.ok(<int>[1, 2, 3, 4])
      ..contentType = ContentType("foo", "bar");
    server = await bindAndRespondWith(response);

    var resp = await http.get("http://localhost:8888");
    var contentType = ContentType.parse(resp.headers["content-type"]);
    expect(resp.statusCode, 200);
    expect(contentType.primaryType, "foo");
    expect(contentType.subType, "bar");
    expect(contentType.charset, null);
    expect(resp.bodyBytes, [1, 2, 3, 4]);
  });

  test(
      "String body, text content-type defaults content to latin1 but does not include in header",
      () async {
    var response = Response.ok("xyz")..contentType = ContentType("text", "bar");
    server = await bindAndRespondWith(response);

    var resp = await http.get("http://localhost:8888");
    var contentType = ContentType.parse(resp.headers["content-type"]);
    expect(resp.statusCode, 200);
    expect(contentType.primaryType, "text");
    expect(contentType.subType, "bar");
    expect(contentType.charset, null);
    expect(resp.body, "xyz");
  });

  test("A decoder with a match-all subtype will be used when matching",
      () async {
    var ct = ContentType("b", "*");
    CodecRegistry.defaultInstance.add(ct, ByteCodec());
    var serverResponse = Response.ok("hello")
      ..contentType = ContentType("b", "bar");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8888");
    expect(resp.statusCode, 200);
    expect(resp.headers["content-type"], "b/bar");
    expect(resp.body, "hello");
  });

  test(
      "A decoder with a subtype always trumps a decoder that matches any subtype",
      () async {
    CodecRegistry.defaultInstance.add(ContentType("a", "*"), ByteCodec());
    CodecRegistry.defaultInstance
        .add(ContentType("a", "specific"), const JsonCodec());

    var serverResponse = Response.ok({"key": "value"})
      ..contentType = ContentType("a", "specific", charset: "utf-8");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8888");
    expect(resp.statusCode, 200);
    expect(resp.headers["content-type"], "a/specific; charset=utf-8");
    expect(json.decode(resp.body), {"key": "value"});
  });

  test("Using an encoder that blows up during encoded returns 500 safely",
      () async {
    CodecRegistry.defaultInstance
        .add(ContentType("application", "crash"), CrashingCodec());
    var serverResponse = Response.ok("abcd")
      ..contentType = ContentType("application", "crash");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8888");
    expect(resp.statusCode, 500);
  });

  test("Invalid charset sends 415", () async {
    var serverResponse = Response.ok("abcd")
      ..contentType = ContentType("text", "plain", charset: "abcd");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8888");
    expect(resp.statusCode, 415);
  });

  test("Encoder that doesn't net out with List<int> safely fails", () async {
    CodecRegistry.defaultInstance.add(
        ContentType("application", "baddata"), BadDataCodec(),
        allowCompression: false);
    var serverResponse = Response.ok("abcd")
      ..contentType = ContentType("application", "baddata");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8888");
    expect(resp.statusCode, 500);
  });

  test("Encode with x-www-form-urlencoded", () {
    final codec = CodecRegistry
      .defaultInstance
      .codecForContentType(ContentType("application", "x-www-form-urlencoded"));

    expect(codec.encode(<String, dynamic>{"k": "v"}), "k=v".codeUnits);
    expect(codec.encode(<String, dynamic>{"k": "v!v"}), "k=v%21v".codeUnits);
    expect(codec.encode(<String, dynamic>{"k1": "v1", "k2": "v2"}), "k1=v1&k2=v2".codeUnits);
    expect(codec.encode(<String, dynamic>{"k": ["v1", "v!"]}), "k=v1&k=v%21".codeUnits);
  });

  group("Compression", () {
    test(
        "Content-Type that can be gzipped and request has Accept-Encoding will be gzipped",
        () async {
      // both gzip and gzip, deflate
      server = await bindAndRespondWith(Response.ok({"a": "b"}));

      var acceptEncodingHeaders = ["gzip", "gzip, deflate", "deflate,gzip"];
      for (var acceptEncoding in acceptEncodingHeaders) {
        var req = await client.getUrl(Uri.parse("http://localhost:8888"));
        req.headers.clear();
        req.headers.add("accept-encoding", acceptEncoding);
        var resp = await req.close();

        expect(resp.statusCode, 200);
        expect(resp.headers.contentType.toString(),
            equals(ContentType.json.toString()));
        expect(resp.headers.value("content-encoding"), "gzip",
            reason: acceptEncoding);
        expect(resp.headers.value("content-length"), isNotNull);
        expect(json.decode(utf8.decode(await resp.first)), {"a": "b"});
      }
    });

    test(
        "Content-Type that can be gzipped but request does not have Accept-Encoding not gzipped",
        () async {
      server = await bindAndRespondWith(Response.ok({"a": "b"}));

      var req = await client.getUrl(Uri.parse("http://localhost:8888"));
      req.headers.clear();
      var resp = await req.close();

      expect(resp.headers.contentType.toString(),
          equals(ContentType.json.toString()));
      expect(resp.headers.value("content-encoding"), isNull);
      expect(resp.headers.value("content-length"), isNotNull);

      expect(resp.statusCode, 200);
      expect(json.decode(utf8.decode(await resp.first)), {"a": "b"});
    });

    test(
        "Content-Type that can be gzipped and request has Accept-Encoding but not gzip",
        () async {
      server = await bindAndRespondWith(Response.ok({"a": "b"}));

      var req = await client.getUrl(Uri.parse("http://localhost:8888"));
      req.headers.clear();
      req.headers.add("accept-encoding", "deflate");
      var resp = await req.close();

      expect(resp.headers.contentType.toString(),
          equals(ContentType.json.toString()));
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(json.decode(utf8.decode(await resp.first)), {"a": "b"});
    });

    test("Unregistered content-type of List<int> does not get gzipped",
        () async {
      var ct = ContentType("application", "1");
      server =
          await bindAndRespondWith(Response.ok([1, 2, 3, 4])..contentType = ct);
      var req = await client.getUrl(Uri.parse("http://localhost:8888"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      var resp = await req.close();

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(await resp.first, [1, 2, 3, 4]);
    });

    test("Can compress without content-type/codec pair", () async {
      var ct = ContentType("application", "2");
      CodecRegistry.defaultInstance.setAllowsCompression(ct, true);
      server =
          await bindAndRespondWith(Response.ok([1, 2, 3, 4])..contentType = ct);
      var req = await client.getUrl(Uri.parse("http://localhost:8888"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      var resp = await req.close();

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), "gzip");

      expect(resp.statusCode, 200);
      expect(await resp.first, [1, 2, 3, 4]);
    });

    test(
        "Content-type that can't be gzipped and Accept-Encoding accepts gzip, not gzipped",
        () async {
      var ct = ContentType("application", "3", charset: "utf-8");
      CodecRegistry.defaultInstance
          .add(ct, const JsonCodec(), allowCompression: false);
      server =
          await bindAndRespondWith(Response.ok({"a": "b"})..contentType = ct);
      var req = await client.getUrl(Uri.parse("http://localhost:8888"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      var resp = await req.close();

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(json.decode(utf8.decode(await resp.first)), {"a": "b"});
    });
  });
}

Future<HttpServer> bindAndRespondWith(Response response) async {
  var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
  server.map((req) => Request(req)).listen((req) async {
    var next = PassthruController();
    next.linkFunction((req) async {
      return response;
    });
    await next.receive(req);
  });

  return server;
}

class ByteCodec extends Codec<dynamic, List<int>> {
  @override
  Converter<dynamic, List<int>> get encoder => const ByteEncoder();
  @override
  Converter<List<int>, dynamic> get decoder => null;
}

class ByteEncoder extends Converter<String, List<int>> {
  const ByteEncoder();
  @override
  List<int> convert(String object) => utf8.encode(object);
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
  List<int> convert(String object) => throw Exception("uhoh");
}

class BadDataCodec extends Codec {
  @override
  Converter get encoder => const BadDataEncoder();
  @override
  Converter get decoder => null;
}

class BadDataEncoder extends Converter<String, String> {
  const BadDataEncoder();
  @override
  String convert(String object) => object;
}
