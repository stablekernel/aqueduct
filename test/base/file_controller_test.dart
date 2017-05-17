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
  var unknownFileExtension = new File.fromUri(fileDirectory.uri.resolve("file.unk"));
  var noFileExtension = new File.fromUri(fileDirectory.uri.resolve("file"));

  HttpServer server;

  setUpAll(() async {
    fileDirectory.createSync();
    jsonFile.writeAsBytesSync(UTF8.encode(JSON.encode(jsonContents)));
    htmlFile.writeAsBytesSync(UTF8.encode(htmlContents));
    unknownFileExtension.writeAsBytesSync(UTF8.encode(htmlContents));
    noFileExtension.writeAsBytesSync(UTF8.encode(htmlContents));

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
  });

  test("Can serve json file",  () async {
    var response = await getFile("file.json");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "application/json; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(JSON.decode(response.body), jsonContents);
  });

  test("Can serve html file",  () async {
    var response = await getFile("file.html");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "text/html; charset=utf-8");
    expect(response.headers["content-encoding"], "gzip");
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.body, htmlContents);
  });

  test("Missing files returns 404", () async {
    var response = await getFile("file.foobar");
    expect(response.statusCode, 404);
  });

  test("Unknown extension-content type is application/octet-stream", () async {
    var response = await getFile("file.unk");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "application/octet-stream");
    expect(response.headers["content-encoding"], isNull);
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.body, htmlContents);
  });

  test("No file extension is application/octet-stream", () async {
    var response = await getFile("file");
    expect(response.statusCode, 200);
    expect(response.headers["content-type"], "application/octet-stream");
    expect(response.headers["content-encoding"], isNull);
    expect(response.headers["transfer-encoding"], "chunked");
    expect(response.body, htmlContents);
  });
}

Future<http.Response> getFile(String path) async {
  return http.get("http://localhost:8081/files/$path");
}