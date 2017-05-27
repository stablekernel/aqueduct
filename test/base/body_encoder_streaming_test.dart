import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  group("Unencoded list of bytes", () {
    HttpServer server;

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Stream a list of bytes as a response", () async {
      var sc = new StreamController<List<int>>();
      var response = new Response.ok(sc.stream)
        ..contentType = new ContentType("application", "octet-stream");
      server = await bindAndRespondWith(response);

      var resultFuture = http.get("http://localhost:8081");

      sc.add([1, 2, 3, 4]);
      sc.add([5, 6, 7, 8]);
      sc.close();

      var result = await resultFuture;
      expect(result.bodyBytes, [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(result.headers["transfer-encoding"], "chunked");
    });

    test("Stream of list of bytes encounters error", () async {
      var sc = new StreamController<List<int>>();
      var response = new Response.ok(sc.stream)
        ..contentType = new ContentType("application", "octet-stream");
      server = await bindAndRespondWith(response);

      var resultFuture = http.get("http://localhost:8081");

      sc.add([1, 2, 3, 4]);
      sc.add([5, 6, 7, 8]);
      sc.addError(new Exception("Whatever"));
      sc.close();

      try {
        await resultFuture;
        expect(true, false);
      } on http.ClientException catch (e) {
        expect(e.toString(), contains("Connection closed while receiving data"));
      }

      expect(serverHasNoMoreConnections(server), completes);
    });

    test("Stream a list of bytes with incorrect content type returns 500", () async {
      var sc = new StreamController<List<int>>();
      var response = new Response.ok(sc.stream)
        ..contentType = new ContentType("application", "json");
      server = await bindAndRespondWith(response);

      var resultFuture = http.get("http://localhost:8081");

      sc.add([1, 2, 3, 4]);
      sc.add([5, 6, 7, 8]);
      sc.close();

      // The test fails for a different reason in checked vs. unchecked mode.
      // Tests run in checked mode, but coverage runs in unchecked mode.
      try {
        var result = await resultFuture;
        expect(result.statusCode, 500);
        expect(result.bodyBytes, []);
      } on http.ClientException catch (_) {}
    });
  });

  group("Streaming codec", () {
    HttpServer server;

    tearDown(() async {
      await server?.close(force: true);
    });

    test("Stream a string as a response (which uses a codec)", () async {
      var sc = new StreamController<String>();
      var response = new Response.ok(sc.stream)
        ..contentType = new ContentType("text", "plain", charset: "utf-8");
      server = await bindAndRespondWith(response);

      var resultFuture = http.get("http://localhost:8081");

      sc.add("abcd");
      sc.add("efgh");
      sc.close();

      var result = await resultFuture;
      expect(result.body, "abcdefgh");
      expect(result.headers["transfer-encoding"], "chunked");
    });

    test("Crash in encoder terminates connection", () async {
      HTTPCodecRepository.defaultInstance.add(new ContentType("application", "crash"), new CrashingCodec());

      var sc = new StreamController<String>();
      var response = new Response.ok(sc.stream)
        ..contentType = new ContentType("application", "crash");
      server = await bindAndRespondWith(response);

      var resultFuture = http.get("http://localhost:8081");

      sc.add("abcd");
      sc.add("efgh");
      sc.close();

      try {
        await resultFuture;
        expect(true, false);
      } on http.ClientException catch (e) {
        expect(e.toString(), contains("Connection closed while receiving data"));
      }

      expect(serverHasNoMoreConnections(server), completes);
    });
  });

  group("Compression", () {
    HttpServer server;
    HttpClient client;

    setUp(() async {
      client = new HttpClient();
    });

    tearDown(() async {
      await server.close();
      client.close(force: true);
    });

    test("Content-Type that can be gzipped but request does not have Accept-Encoding not gzipped", () async {
      var sc = new StreamController<String>();
      server = await bindAndRespondWith(new Response.ok(sc.stream)..contentType = ContentType.TEXT);

      var req = await client.getUrl(Uri.parse("http://localhost:8081"));
      req.headers.clear();

      var respFuture = req.close();

      sc.add("abcd");
      sc.add("efgh");
      sc.close();

      var resp = await respFuture;

      expect(resp.headers.contentType.toString(), equals(ContentType.TEXT.toString()));
      expect(resp.headers.value("content-encoding"), isNull);
      expect(resp.headers.value("transfer-encoding"), "chunked");
      expect(resp.headers.value("content-length"), isNull);

      expect(resp.statusCode, 200);
      var allBody = (await resp.toList()).expand((i) => i).toList();
      expect(UTF8.decode(allBody), "abcdefgh");
    });

    test("Content-Type that can be gzipped and request has Accept-Encoding but not gzip doesn't get gzipped", () async {
      var sc = new StreamController<String>();
      server = await bindAndRespondWith(new Response.ok(sc.stream)..contentType = ContentType.TEXT);

      var req = await client.getUrl(Uri.parse("http://localhost:8081"));
      req.headers.clear();
      req.headers.add("accept-encoding", "deflate");
      var respFuture = req.close();

      sc.add("abcd");
      sc.add("efgh");
      sc.close();

      var resp = await respFuture;

      expect(resp.headers.contentType.toString(), equals(ContentType.TEXT.toString()));
      expect(resp.headers.value("content-encoding"), isNull);
      expect(resp.headers.value("transfer-encoding"), "chunked");
      expect(resp.headers.value("content-length"), isNull);

      expect(resp.statusCode, 200);
      var allBody = (await resp.toList()).expand((i) => i).toList();
      expect(UTF8.decode(allBody), "abcdefgh");
    });

    test("Unregistered content-type of Stream<List<int>> does not get gzipped", () async {
      var sc = new StreamController<List<int>>();
      var ct = new ContentType("application", "1");
      server = await bindAndRespondWith(new Response.ok(sc.stream)..contentType = ct);
      var req = await client.getUrl(Uri.parse("http://localhost:8081"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      var respFuture = req.close();

      sc.add([1, 2, 3, 4]);
      sc.close();

      var resp = await respFuture;

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(await resp.first, [1, 2, 3, 4]);
    });

    test("Content-type that can't be gzipped and Accept-Encoding accepts gzip, not gzipped", () async {
      var sc = new StreamController<String>();
      var ct = new ContentType("application", "3");
      HTTPCodecRepository.defaultInstance.add(ct, new Utf8Codec(), allowCompression: false);
      server = await bindAndRespondWith(new Response.ok(sc.stream)..contentType = ct);
      var req = await client.getUrl(Uri.parse("http://localhost:8081"));
      req.headers.clear();
      req.headers.add("accept-encoding", "gzip");
      var respFuture = req.close();

      sc.add("abcd");
      sc.close();

      var resp = await respFuture;

      expect(resp.headers.contentType.toString(), ct.toString());
      expect(resp.headers.value("content-encoding"), isNull);

      expect(resp.statusCode, 200);
      expect(UTF8.decode(await resp.first), "abcd");
    });
  });

  group("Client cancellation", () {
    HttpServer server;

    tearDown(() async {
      await server.close(force: true);
    });

    test("Client request is cancelled during stream cleans up appropriately", () async {
      var sc = new StreamController<List<int>>();
      var response = new Response.ok(sc.stream)
        ..contentType = new ContentType("application", "octet-stream");
      var initiateResponseCompleter = new Completer();
      server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
      server.map((req) => new Request(req)).listen((req) async {
        var next = new RequestController();
        next.listen((req) async {
          initiateResponseCompleter.complete();
          return response;
        });
        await next.receive(req);
      });

      var socket = await Socket.connect("localhost", 8081);
      var request = "GET /r HTTP/1.1\r\nConnection: keep-alive\r\nHost: localhost\r\n\r\n";
      socket.add(request.codeUnits);

      await initiateResponseCompleter.future;

      sc.add([1, 2, 3, 4]);
      expect(server.connectionsInfo().active, 1);

      await socket.close();
      socket.destroy();
      await sc.close();

      expect(serverHasNoMoreConnections(server), completes);
    });
  });
}

Future serverHasNoMoreConnections(HttpServer server) async {
  if (server.connectionsInfo().total == 0) {
    return null;
  }

  await new Future.delayed(new Duration(milliseconds: 100));

  return serverHasNoMoreConnections(server);
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

class CrashingCodec extends Codec {
  @override
  CrashingEncoder get encoder => new CrashingEncoder();
  @override
  Converter get decoder => null;
}

class CrashingEncoder extends Converter<String, List<int>> {
  @override
  List<int> convert(String val) => [];

  @override
  CrashingSink startChunkedConversion(Sink<List<int>> sink) {
    return new CrashingSink(sink);
  }
}

class CrashingSink extends ChunkedConversionSink<String> {
  CrashingSink(this.sink);

  Sink<List<int>> sink;
  int count = 0;
  @override

  void add(String chunk) {
    count += chunk.length;
    if (count > 4) {
      throw new Exception("uhoh");
    }
    sink.add([1]);
  }

  @override
  void close() {

  }
}

