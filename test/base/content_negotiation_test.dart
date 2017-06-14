import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:io';

void main() {
  HttpServer server;
  Request request;
  HttpClient client;

  setUpAll(() {
    client = new HttpClient();
  });

  tearDownAll(() async {
    client.close(force: true);
  });

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8123);
  });

  tearDown(() async {
    await request?.innerRequest?.response?.close();
    await server?.close(force: true);
  });

  test("No accept header returns [], all are allowed", () async {
    getWithTypes(client, null);
    request = new Request(await server.first);
    expect(request.acceptableContentTypes, []);
    expect(request.acceptsContentType(ContentType.JSON), true);
    expect(request.acceptsContentType(ContentType.HTML), true);
    expect(request.acceptsContentType(ContentType.BINARY), true);
  });

  test("Empty Accept header returns [], all are allowed", () async {
    getWithTypes(client, []);
    request = new Request(await server.first);

    expect(request.acceptableContentTypes.isEmpty, true);
    expect(request.acceptsContentType(ContentType.JSON), true);
    expect(request.acceptsContentType(ContentType.HTML), true);
    expect(request.acceptsContentType(ContentType.BINARY), true);
  });

  test("Two implicitly equal q-values order is defined by their position in request", () async {
    getWithTypes(client, ["text/plain", "text/html"]);
    request = new Request(await server.first);
    expect(request.acceptableContentTypes.any((ct) => ct.primaryType == "text" && ct.subType == "plain"), true);
    expect(request.acceptableContentTypes.any((ct) => ct.primaryType == "text" && ct.subType == "html"), true);
    expect(request.acceptsContentType(ContentType.JSON), false);
    expect(request.acceptsContentType(ContentType.HTML), true);
    expect(request.acceptsContentType(ContentType.TEXT), true);
    expect(request.acceptsContentType(ContentType.BINARY), false);
  });

  test("Two explicitly equal q-values order is defined by their position in request", () async {
    getWithTypes(client, ["text/plain; q=1.0", "text/html; q=1.0"]);
    request = new Request(await server.first);
    expect(request.acceptableContentTypes.first.primaryType == "text" && request.acceptableContentTypes.first.subType == "plain", true);
    expect(request.acceptableContentTypes.last.primaryType == "text" && request.acceptableContentTypes.last.subType == "html", true);
    expect(request.acceptsContentType(ContentType.JSON), false);
    expect(request.acceptsContentType(ContentType.HTML), true);
    expect(request.acceptsContentType(ContentType.TEXT), true);
    expect(request.acceptsContentType(ContentType.BINARY), false);
  });

  test("Q-value with explicit 1 (not 1.0) is interpreted as 1.0", () async {
    getWithTypes(client, ["text/plain; q=1.0", "text/html; q=1"]);
    request = new Request(await server.first);
    expect(request.acceptableContentTypes.first.primaryType == "text" && request.acceptableContentTypes.first.subType == "plain", true);
    expect(request.acceptableContentTypes.last.primaryType == "text" && request.acceptableContentTypes.last.subType == "html", true);
    expect(request.acceptsContentType(ContentType.JSON), false);
    expect(request.acceptsContentType(ContentType.HTML), true);
    expect(request.acceptsContentType(ContentType.TEXT), true);
    expect(request.acceptsContentType(ContentType.BINARY), false);
  });

  test("Two equal q-values but primary type is * prefers to other type", () async {
    getWithTypes(client, ["*/*", "text/html"]);
    request = new Request(await server.first);
    expect(request.acceptableContentTypes.first.primaryType == "text" && request.acceptableContentTypes.first.subType == "html", true);
    expect(request.acceptableContentTypes.last.primaryType == "*" && request.acceptableContentTypes.last.subType == "*", true);
    expect(request.acceptsContentType(ContentType.JSON), true);
    expect(request.acceptsContentType(ContentType.HTML), true);
    expect(request.acceptsContentType(ContentType.TEXT), true);
    expect(request.acceptsContentType(ContentType.BINARY), true);
  });

  test("Two equal q-values but subtype is * prefers to other type", () async {
    getWithTypes(client, ["text/*", "text/html"]);
    request = new Request(await server.first);
    expect(request.acceptableContentTypes.first.primaryType == "text" && request.acceptableContentTypes.first.subType == "html", true);
    expect(request.acceptableContentTypes.last.primaryType == "text" && request.acceptableContentTypes.last.subType == "*", true);
    expect(request.acceptsContentType(ContentType.JSON), false);
    expect(request.acceptsContentType(ContentType.HTML), true);
    expect(request.acceptsContentType(ContentType.TEXT), true);
    expect(request.acceptsContentType(ContentType.BINARY), false);
  });

  test("Sorted by q-value if all content-types are fully defined", () async {
    getWithTypes(client, ["text/plain; q=0.4", "text/html; q=0.8", "application/json; charset=utf-8"]);
    request = new Request(await server.first);
    expect(request.acceptableContentTypes.first.primaryType == "application" && request.acceptableContentTypes.first.subType == "json", true);
    expect(request.acceptableContentTypes[1].primaryType == "text" && request.acceptableContentTypes[1].subType == "html", true);
    expect(request.acceptableContentTypes.last.primaryType == "text" && request.acceptableContentTypes.last.subType == "plain", true);
    expect(request.acceptsContentType(ContentType.JSON), true);
    expect(request.acceptsContentType(ContentType.HTML), true);
    expect(request.acceptsContentType(ContentType.TEXT), true);
    expect(request.acceptsContentType(ContentType.BINARY), false);
  });
}

Future getWithTypes(HttpClient client, List<String> contentTypeStrings) async {
  var req = await client.openUrl("GET", Uri.parse("http://localhost:8123"));
  if (contentTypeStrings != null) {
    if (contentTypeStrings.isEmpty) {
      req.headers.set(HttpHeaders.ACCEPT, "");
    } else {
      req.headers.add(HttpHeaders.ACCEPT, contentTypeStrings.join(", "));
    }
  }

  var response = await req.close();
  return response.drain();
}