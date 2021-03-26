import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  var client = HttpClient();
  var fileDirectory = Directory("temp_files");
  var jsonContents = {"key": "value"};
  var cssContents = "a { color: red; }";
  var jsContents = "f() {}";
  var htmlContents = "<html><h3>Aqueduct</h3></html>";
  var jsonFile = File.fromUri(fileDirectory.uri.resolve("file.json"));
  var cssFile = File.fromUri(fileDirectory.uri.resolve("file.css"));
  var jsFile = File.fromUri(fileDirectory.uri.resolve("file.js"));
  var htmlFile = File.fromUri(fileDirectory.uri.resolve("file.html"));
  var indexFile = File.fromUri(fileDirectory.uri.resolve("index.html"));
  var unknownFileExtension =
      File.fromUri(fileDirectory.uri.resolve("file.unk"));
  var noFileExtension = File.fromUri(fileDirectory.uri.resolve("file"));
  var sillyFileExtension =
      File.fromUri(fileDirectory.uri.resolve("file.silly"));
  var subdir = Directory.fromUri(fileDirectory.uri.resolve("subdir/"));
  var subdirFile = File.fromUri(subdir.uri.resolve("index.html"));

  HttpServer server;

  setUpAll(() async {
    fileDirectory.createSync();
    subdir.createSync();

    jsonFile.writeAsBytesSync(utf8.encode(json.encode(jsonContents)));
    htmlFile.writeAsBytesSync(utf8.encode(htmlContents));
    unknownFileExtension.writeAsBytesSync(utf8.encode(htmlContents));
    noFileExtension.writeAsBytesSync(utf8.encode(htmlContents));
    indexFile.writeAsBytesSync(utf8.encode(htmlContents));
    subdirFile.writeAsBytesSync(utf8.encode(htmlContents));
    sillyFileExtension.writeAsBytesSync(utf8.encode(htmlContents));
    cssFile.writeAsBytesSync(utf8.encode(cssContents));
    jsFile.writeAsBytesSync(utf8.encode(jsContents));

    var cachingController = FileController("temp_files")
      ..addCachePolicy(const CachePolicy(requireConditionalRequest: true),
          (path) => path.endsWith(".html"))
      ..addCachePolicy(
          const CachePolicy(expirationFromNow: Duration(seconds: 31536000)),
          (path) => [
                ".jpg",
                ".js",
                ".png",
                ".css",
                ".jpeg",
                ".ttf",
                ".eot",
                ".woff",
                ".otf"
              ].any((suffix) => path.endsWith(suffix)));

    var router = Router()
      ..route("/files/*").link(() => FileController("temp_files"))
      ..route("/redirect/*").link(
          () => FileController("temp_files", onFileNotFound: (c, r) async {
                return Response.ok({"k": "v"});
              }))
      ..route("/cache/*").link(() => cachingController)
      ..route("/silly/*").link(() => FileController("temp_files")
        ..setContentTypeForExtension(
            "silly", ContentType("text", "html", charset: "utf-8")));
    router.didAddToChannel();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
    server.map((r) => Request(r)).listen((req) {
      router.receive(req);
    });
  });

  tearDownAll(() {
    fileDirectory.deleteSync(recursive: true);
    client.close(force: true);
    server.close(force: true);
  });

  test("Can serve json file", () async {
    var response = await getFile("/file.json");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "application/json; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.headers["cache-control"], isNull);
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(json.decode(response.body), jsonContents);
  });

  test("Can serve html file", () async {
    var response = await getFile("/file.html");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.headers["cache-control"], isNull);
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);
  });

  test("Missing files returns 404", () async {
    var response = await getFile("/file.foobar");
    expect(response.headers["last-modified"], isNull);
    expect(response.headers["cache-control"], isNull);
    expect(response.headers["content-type"], "text/html; charset=utf-8");

    expect(response.statusCode, 404);
    expect(response.body, contains("<html>"));
  });

  test(
      "If 404 response to request without Accept: text/html, do not include HTML body",
      () async {
    var response = await getFile("/file.foobar",
        headers: {HttpHeaders.acceptHeader: "text/plain"});
    expect(response.headers["last-modified"], isNull);
    expect(response.headers["cache-control"], isNull);
    expect(response.headers["content-type"], isNull);

    expect(response.statusCode, 404);
    expect(response.body, isEmpty);
  });

  test("Unknown extension-content type is application/octet-stream", () async {
    var response = await getFile("/file.unk");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "application/octet-stream");
    expect(response.headers["content-encoding"], isNull);
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.headers["cache-control"], isNull);
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);
  });

  test("No file extension is application/octet-stream", () async {
    var response = await getFile("/file");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "application/octet-stream");
    expect(response.headers["content-encoding"], isNull);
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.headers["cache-control"], isNull);
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);

    expect(response.body, htmlContents);
  });

  test("If no file specified, serve index.html", () async {
    var response = await getFile("/");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.headers["cache-control"], isNull);
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);

    expect(response.body, htmlContents);
  });

  test("Serve out of subdir", () async {
    var response = await getFile("/subdir/index.html");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.headers["cache-control"], isNull);
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);
  });

  test("Subdir with trailing/ serves index.html", () async {
    var response = await getFile("/subdir/");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.headers["cache-control"], isNull);
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);
  });

  test("Attempt to reference file as directory yields 404", () async {
    var response = await getFile("/index.html/");
    expect(response.statusCode, 404);
  });

  test("Subdir without trailing/ serves index.html", () async {
    var response = await getFile("/subdir");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.headers["cache-control"], isNull);
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);
  });

  test("Can add extension", () async {
    var response = await http.get("http://localhost:8888/silly/file.silly");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.headers["cache-control"], isNull);
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);
  });

  test("Client connection closed before data is sent still shuts down stream",
      () async {
    var socket = await Socket.connect("localhost", 8888);
    var request =
        "GET /files/file.html HTTP/1.1\r\nConnection: keep-alive\r\nHost: localhost\r\n\r\n";
    socket.add(request.codeUnits);
    await socket.flush();
    socket.destroy();

    var response = await getFile("/file.html");
    expect(response.statusCode, 200);
    expect(response.body, htmlContents);

    expect(serverHasNoMoreConnections(server), completes);
  });

  test("Provide onFileNotFound provides another response", () async {
    var response =
        await http.get("http://localhost:8888/redirect/jkasdjlkasjdksadj");
    expect(response.statusCode, 200);
    expect(json.decode(response.body), {"k": "v"});
  });

  group("Default caching", () {
    test("Uncached file has no cache-control", () async {
      var response = await getCacheableFile("/file.json");
      expect(response.statusCode, 200);
      expect(
          response.headers["content-type"], "application/json; charset=utf-8");
      expect(response.headers["content-encoding"], "gzip");
      expect(response.headers["transfer-encoding"], "chunked");
      expect(response.headers["cache-control"], isNull);
      expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
      expect(json.decode(response.body), jsonContents);
    });

    test("HTML file has no-cache", () async {
      var response = await getCacheableFile("/file.html");
      expect(response.statusCode, 200);
      expect(response.headers["content-type"], "text/html; charset=utf-8");
      expect(response.headers["content-encoding"], "gzip");
      expect(response.headers["transfer-encoding"], "chunked");
      expect(response.headers["cache-control"], "public, no-cache");
      expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
      expect(response.body, htmlContents);
    });

    test(
        "Fetch file with If-Modified-Since before last modified date, returns file",
        () async {
      var response =
          await getCacheableFile("/file.html", ifModifiedSince: DateTime(2000));
      expect(response.statusCode, 200);
      expect(response.headers["content-type"], "text/html; charset=utf-8");
      expect(response.headers["content-encoding"], "gzip");
      expect(response.headers["transfer-encoding"], "chunked");
      expect(response.headers["cache-control"], "public, no-cache");
      expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
      expect(response.body, htmlContents);
    });

    test(
        "Fetch file with If-Modified-Since after last modified date, returns 304 with no body",
        () async {
      var response = await getCacheableFile("/file.html",
          ifModifiedSince: DateTime.now().add(const Duration(hours: 1)));
      expect(response.statusCode, 304);
      expect(response.headers["content-type"], isNull);
      expect(response.headers["content-encoding"], isNull);
      expect(response.headers["transfer-encoding"], isNull);
      expect(response.headers["cache-control"], "public, no-cache");
      expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
      expect(response.body.isEmpty, true);
    });

    test("JS file has large max-age", () async {
      var response = await getCacheableFile("/file.js");
      expect(response.statusCode, 200);
      expect(response.headers["content-type"],
          "application/javascript; charset=utf-8");
      expect(response.headers["content-encoding"], "gzip");
      expect(response.headers["transfer-encoding"], "chunked");
      expect(response.headers["cache-control"], "public, max-age=31536000");
      expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
      expect(response.body, jsContents);
    });

    test("CSS file has large max-age", () async {
      var response = await getCacheableFile("/file.css");
      expect(response.statusCode, 200);
      expect(response.headers["content-type"], "text/css; charset=utf-8");
      expect(response.headers["content-encoding"], "gzip");
      expect(response.headers["transfer-encoding"], "chunked");
      expect(response.headers["cache-control"], "public, max-age=31536000");
      expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
      expect(response.body, cssContents);
    });
  });
}

Future<http.Response> getFile(String path,
    {Map<String, String> headers}) async {
  return http.get("http://localhost:8888/files$path", headers: headers);
}

Future<http.Response> getCacheableFile(String path,
    {DateTime ifModifiedSince}) async {
  if (ifModifiedSince == null) {
    return http.get("http://localhost:8888/cache$path");
  }

  return http.get("http://localhost:8888/cache$path", headers: {
    HttpHeaders.ifModifiedSinceHeader: HttpDate.format(ifModifiedSince)
  });
}

Future serverHasNoMoreConnections(HttpServer server) async {
  if (server.connectionsInfo().total == 0) {
    return null;
  }

  await Future.delayed(const Duration(milliseconds: 100));

  return serverHasNoMoreConnections(server);
}
