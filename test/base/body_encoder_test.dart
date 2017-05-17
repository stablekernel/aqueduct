import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

void main() {
  HttpServer server = null;
  HttpClient client = null;

  setUp(() async {
    client = new HttpClient();
  });

  tearDown(() async {
    await server.close();
    client.close(force: true);
  });
  
  test("Using an encoder that doesn't exist with a non-List<int> returns a 500", () async {
    var response = new Response.ok("xyz")
      ..contentType = new ContentType("foo", "bar");
    server = await bindAndRespondWith(response);

    var resp = await http.get("http://localhost:8081");
    var contentType = ContentType.parse(resp.headers["content-type"]);
    expect(resp.statusCode, 500);
    expect(contentType.primaryType, "text");
    expect(contentType.subType, "plain");
    expect(resp.body, "");
  });

  test("Using an encoder that doesn't exist with a List<int> is OK", () async {
    var response = new Response.ok(<int>[1, 2, 3, 4])
      ..contentType = new ContentType("foo", "bar");
    server = await bindAndRespondWith(response);

    var resp = await http.get("http://localhost:8081");
    var contentType = ContentType.parse(resp.headers["content-type"]);
    expect(resp.statusCode, 200);
    expect(contentType.primaryType, "foo");
    expect(contentType.subType, "bar");
    expect(contentType.charset, null);
    expect(resp.bodyBytes, [1, 2, 3, 4]);
  });

  test("String body, text content-type defaults content to latin1 but does not include in header", () async {
    var response = new Response.ok("xyz")
      ..contentType = new ContentType("text", "bar");
    server = await bindAndRespondWith(response);

    var resp = await http.get("http://localhost:8081");
    var contentType = ContentType.parse(resp.headers["content-type"]);
    expect(resp.statusCode, 200);
    expect(contentType.primaryType, "text");
    expect(contentType.subType, "bar");
    expect(contentType.charset, null);
    expect(resp.body, "xyz");
  });

  test("A decoder with a match-all subtype will be used when matching",
      () async {
    var ct = new ContentType("b", "*");
    HTTPCodecRepository.defaultInstance.add(ct, new ByteCodec());
    var serverResponse = new Response.ok("hello")
      ..contentType = new ContentType("b", "bar");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8081");
    expect(resp.statusCode, 200);
    expect(resp.headers["content-type"], "b/bar");
    expect(resp.body, "hello");
  });

  test(
      "A decoder with a subtype always trumps a decoder that matches any subtype",
      () async {
    HTTPCodecRepository.defaultInstance.add(new ContentType("a", "*"), new ByteCodec());
    HTTPCodecRepository.defaultInstance.add(new ContentType("a", "specific"), new JsonCodec());

    var serverResponse = new Response.ok({"key":"value"})
      ..contentType = new ContentType("a", "specific", charset: "utf-8");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8081");
    expect(resp.statusCode, 200);
    expect(resp.headers["content-type"], "a/specific; charset=utf-8");
    expect(JSON.decode(resp.body), {"key":"value"});
  });

  test("Using an encoder that blows up during encoded returns 500 safely",
      () async {
    HTTPCodecRepository.defaultInstance.add(new ContentType("application", "crash"), new CrashingCodec());
    var serverResponse = new Response.ok("abcd")
      ..contentType = new ContentType("application", "crash");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8081");
    expect(resp.statusCode, 500);
  });

  test("Invalid charset throws 500 safely", () async {
    var serverResponse = new Response.ok("abcd")
      ..contentType = new ContentType("text", "foo", charset: "abcd");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8081");
    expect(resp.statusCode, 500);
  });

  test("Encoder that doesn't net out with List<int> safely fails", () async {
    HTTPCodecRepository.defaultInstance.add(
        new ContentType("application", "baddata"), new BadDataCodec(), allowCompression: false);
    var serverResponse = new Response.ok("abcd")
      ..contentType = new ContentType("application", "baddata");
    server = await bindAndRespondWith(serverResponse);

    var resp = await http.get("http://localhost:8081");
    expect(resp.statusCode, 500);
  });

  group("Compression", () {
    test("Content-Type that can be gzipped and request has Accept-Encoding will be gzipped", () async {
      // both gzip and gzip, deflate
      server = await bindAndRespondWith(new Response.ok({"a": "b"}));

      var acceptEncodingHeaders = ["gzip", "gzip, deflate", "deflate,gzip"];
      for (var acceptEncoding in acceptEncodingHeaders) {
        var req = await client.getUrl(Uri.parse("http://localhost:8081"));
        req.headers.clear();
        req.headers.add("accept-encoding", acceptEncoding);
        var resp = await req.close();

        expect(resp.statusCode, 200);
        expect(resp.headers.contentType.toString(), equals(ContentType.JSON.toString()));
        expect(resp.headers.value("content-encoding"), "gzip", reason: acceptEncoding);
        expect(resp.headers.value("content-length"), isNotNull);
        expect(JSON.decode(UTF8.decode(await resp.first)), {"a":"b"});
      }
    });

    test("Content-Type that can be gzipped but request does not have Accept-Encoding not gzipped", () async {
      server = await bindAndRespondWith(new Response.ok({"a": "b"}));

      var req = await client.getUrl(Uri.parse("http://localhost:8081"));
      req.headers.clear();
      var resp = await req.close();

      expect(resp.headers.contentType.toString(), equals(ContentType.JSON.toString()));
      expect(resp.headers.value("content-encoding"), isNull);
      expect(resp.headers.value("content-length"), isNotNull);

      expect(resp.statusCode, 200);
      expect(JSON.decode(UTF8.decode(await resp.first)), {"a":"b"});
    });

    test("Content-Type that can be gzipped and request has Accept-Encoding but not gzip", () async {
      server = await bindAndRespondWith(new Response.ok({"a": "b"}));

      var req = await client.getUrl(Uri.parse("http://localhost:8081"));
      req.headers.clear();
      req.headers.add("accept-encoding", "deflate");
      var resp = await req.close();

      expect(resp.headers.contentType.toString(), equals(ContentType.JSON.toString()));
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(JSON.decode(UTF8.decode(await resp.first)), {"a":"b"});
    });

    test("Unregistered content-type of List<int> does not get gzipped", () async {
      var ct = new ContentType("application", "1");
      server = await bindAndRespondWith(new Response.ok([1, 2, 3, 4])..contentType = ct);
      var req = await client.getUrl(Uri.parse("http://localhost:8081"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      var resp = await req.close();

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(await resp.first, [1, 2, 3, 4]);
    });

    test("Can compress without content-type/codec pair", () async {
      var ct = new ContentType("application", "2");
      HTTPCodecRepository.defaultInstance.setAllowsCompression(ct, true);
      server = await bindAndRespondWith(new Response.ok([1, 2, 3, 4])..contentType = ct);
      var req = await client.getUrl(Uri.parse("http://localhost:8081"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      var resp = await req.close();

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), "gzip");

      expect(resp.statusCode, 200);
      expect(await resp.first, [1, 2, 3, 4]);
    });

    test("Content-type that can't be gzipped and Accept-Encoding accepts gzip, not gzipped", () async {
      var ct = new ContentType("application", "3", charset: "utf-8");
      HTTPCodecRepository.defaultInstance.add(ct, new JsonCodec(), allowCompression: false);
      server = await bindAndRespondWith(new Response.ok({"a": "b"})..contentType = ct);
      var req = await client.getUrl(Uri.parse("http://localhost:8081"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      var resp = await req.close();

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(JSON.decode(UTF8.decode(await resp.first)), {"a":"b"});
    });
  });
}

Future<HttpServer> bindAndRespondWith(Response response) async {
  var server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
  server.map((req) => new Request(req)).listen((req) async {
    var next = new RequestController();
    next.listen((req) async {
      return response;
    });
    await next.receive(req);
  });

  return server;
}

class ByteCodec extends Codec {
  Converter get encoder => const ByteEncoder();
  Converter get decoder => null;
}

class ByteEncoder extends Converter<String, List<int>> {
  const ByteEncoder();
  List<int> convert(String object) => UTF8.encode(object);
}

class CrashingCodec extends Codec {
  Converter get encoder => const CrashingEncoder();
  Converter get decoder => null;
}

class CrashingEncoder extends Converter<String, List<int>> {
  const CrashingEncoder();
  List<int> convert(String object) => throw new Exception("uhoh");
}

class BadDataCodec extends Codec {
  Converter get encoder => const BadDataEncoder ();
  Converter get decoder => null;
}

class BadDataEncoder extends Converter<String, String> {
  const BadDataEncoder ();
  String convert(String object) => object;
}

