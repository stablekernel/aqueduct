import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  var client = new HttpClient();
  var fileDirectory = new Directory("temp_files");
  var jsonContents = {"key": "value"};
  var htmlContents = "<html><h3>Aqueduct</h3></html>";
  var jsonFile = new File.fromUri(fileDirectory.uri.resolve("file.json"));
  var htmlFile = new File.fromUri(fileDirectory.uri.resolve("file.html"));
  var indexFile = new File.fromUri(fileDirectory.uri.resolve("index.html"));
  var unknownFileExtension = new File.fromUri(fileDirectory.uri.resolve("file.unk"));
  var noFileExtension = new File.fromUri(fileDirectory.uri.resolve("file"));
  var sillyFileExtension = new File.fromUri(fileDirectory.uri.resolve("file.silly"));
  var subdir = new Directory.fromUri(fileDirectory.uri.resolve("subdir/"));
  var subdirFile = new File.fromUri(subdir.uri.resolve("a.html"));

  HttpServer server;

  setUpAll(() async {
    fileDirectory.createSync();
    subdir.createSync();

    jsonFile.writeAsBytesSync(UTF8.encode(JSON.encode(jsonContents)));
    htmlFile.writeAsBytesSync(UTF8.encode(htmlContents));
    unknownFileExtension.writeAsBytesSync(UTF8.encode(htmlContents));
    noFileExtension.writeAsBytesSync(UTF8.encode(htmlContents));
    indexFile.writeAsBytesSync(UTF8.encode(htmlContents));
    subdirFile.writeAsBytesSync(UTF8.encode(htmlContents));
    sillyFileExtension.writeAsBytesSync(UTF8.encode(htmlContents));

    var router = new Router()
      ..route("/files/*").pipe(new HTTPFileController("temp_files"));
    router.finalize();

    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8081);
    server.map((r) => new Request(r)).listen((req) {
      router.receive(req);
    });
  });

  tearDownAll(() {
    fileDirectory.deleteSync(recursive: true);
    client.close(force: true);
    server.close(force: true);
  });

  test("Can serve json file",  () async {
    var response = await getFile("file.json");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "application/json; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(JSON.decode(response.body), jsonContents);
  });

  test("Can serve html file",  () async {
    var response = await getFile("file.html");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);
  });

  test("Missing files returns 404", () async {
    var response = await getFile("file.foobar");
    expect(response.headers["last-modified"], isNull);

    expect(response.statusCode, 404);
  });

  test("Unknown extension-content type is application/octet-stream", () async {
    var response = await getFile("file.unk");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "application/octet-stream");
    expect(response.headers["content-encoding"], isNull);
    expect(response.headers["transfer-encoding"], "chunked");
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);
  });

  test("No file extension is application/octet-stream", () async {
    var response = await getFile("file");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "application/octet-stream");
    expect(response.headers["content-encoding"], isNull);
    expect(response.headers["transfer-encoding"], "chunked");
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);

    expect(response.body, htmlContents);
  });

  test("If no file specified, serve index.html", () async {
    var response = await getFile("");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);

    expect(response.body, htmlContents);
  });

  test("Serve out of subdir", () async {
    var response = await getFile("subdir/a.html");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);

    response = await getFile("subdir/");
    expect(response.statusCode, 404);
  });

  test("Can add extension", () async {
    HTTPFileController.setContentTypeForExtension("silly", new ContentType("text", "html", charset: "utf-8"));
    var response = await getFile("file.silly");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(HttpDate.parse(response.headers["last-modified"]), isNotNull);
    expect(response.body, htmlContents);
  });

  test("Client connection closed before data is sent still shuts down stream", () async {
    var socket = await Socket.connect("localhost", 8081);
    var request = "GET /files/file.html HTTP/1.1\r\nConnection: keep-alive\r\nHost: localhost\r\n\r\n";
    socket.add(request.codeUnits);
    await socket.flush();
    await socket.close();

    var response = await getFile("file.html");
    expect(response.statusCode, 200);
    expect(response.body, htmlContents);

    expect(serverHasNoMoreConnections(server), completes);
  });
}

Future<http.Response> getFile(String path) async {
  return http.get("http://localhost:8081/files/$path");
}

Future serverHasNoMoreConnections(HttpServer server) async {
  if (server.connectionsInfo().total == 0) {
    return null;
  }

  await new Future.delayed(new Duration(milliseconds: 100));

  return serverHasNoMoreConnections(server);
}