import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  HttpServer server;
  Request request;
  HttpClient client;

  setUpAll(() {
    client = HttpClient();
  });

  tearDownAll(() async {
    client.close(force: true);
  });

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
  });

  tearDown(() async {
    await request?.raw?.response?.close();
    await server?.close(force: true);
  });

  test("No accept header returns [], all are allowed", () async {
    // ignore: unawaited_futures
    getWithTypes(client, null);
    request = Request(await server.first);
    expect(request.acceptableContentTypes, []);
    expect(request.acceptsContentType(ContentType.json), true);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.binary), true);
  });

  test("Empty Accept header returns [], all are allowed", () async {
    // ignore: unawaited_futures
    getWithTypes(client, []);
    request = Request(await server.first);

    expect(request.acceptableContentTypes.isEmpty, true);
    expect(request.acceptsContentType(ContentType.json), true);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.binary), true);
  });

  test(
      "Two implicitly equal q-values order is defined by their position in request",
      () async {
    // ignore: unawaited_futures
    getWithTypes(client, ["text/plain", "text/html"]);
    request = Request(await server.first);
    expect(
        request.acceptableContentTypes
            .any((ct) => ct.primaryType == "text" && ct.subType == "plain"),
        true);
    expect(
        request.acceptableContentTypes
            .any((ct) => ct.primaryType == "text" && ct.subType == "html"),
        true);
    expect(request.acceptsContentType(ContentType.json), false);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.text), true);
    expect(request.acceptsContentType(ContentType.binary), false);
  });

  test(
      "Two explicitly equal q-values order is defined by their position in request",
      () async {
        // ignore: unawaited_futures
    getWithTypes(client, ["text/plain; q=1.0", "text/html; q=1.0"]);
    request = Request(await server.first);
    expect(
        request.acceptableContentTypes.first.primaryType == "text" &&
            request.acceptableContentTypes.first.subType == "plain",
        true);
    expect(
        request.acceptableContentTypes.last.primaryType == "text" &&
            request.acceptableContentTypes.last.subType == "html",
        true);
    expect(request.acceptsContentType(ContentType.json), false);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.text), true);
    expect(request.acceptsContentType(ContentType.binary), false);
  });

  test("Q-value with explicit 1 (not 1.0) is interpreted as 1.0", () async {
    // ignore: unawaited_futures
    getWithTypes(client, ["text/plain; q=1.0", "text/html; q=1"]);
    request = Request(await server.first);
    expect(
        request.acceptableContentTypes.first.primaryType == "text" &&
            request.acceptableContentTypes.first.subType == "plain",
        true);
    expect(
        request.acceptableContentTypes.last.primaryType == "text" &&
            request.acceptableContentTypes.last.subType == "html",
        true);
    expect(request.acceptsContentType(ContentType.json), false);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.text), true);
    expect(request.acceptsContentType(ContentType.binary), false);
  });

  test("Two equal q-values but primary type is * prefers to other type",
      () async {
        // ignore: unawaited_futures
    getWithTypes(client, ["*/*", "text/html"]);
    request = Request(await server.first);
    expect(
        request.acceptableContentTypes.first.primaryType == "text" &&
            request.acceptableContentTypes.first.subType == "html",
        true);
    expect(
        request.acceptableContentTypes.last.primaryType == "*" &&
            request.acceptableContentTypes.last.subType == "*",
        true);
    expect(request.acceptsContentType(ContentType.json), true);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.text), true);
    expect(request.acceptsContentType(ContentType.binary), true);
  });

  test("Two equal q-values but subtype is * prefers to other type", () async {
    // ignore: unawaited_futures
    getWithTypes(client, ["text/*", "text/html"]);
    request = Request(await server.first);
    expect(
        request.acceptableContentTypes.first.primaryType == "text" &&
            request.acceptableContentTypes.first.subType == "html",
        true);
    expect(
        request.acceptableContentTypes.last.primaryType == "text" &&
            request.acceptableContentTypes.last.subType == "*",
        true);
    expect(request.acceptsContentType(ContentType.json), false);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.text), true);
    expect(request.acceptsContentType(ContentType.binary), false);
  });

  test("Sorted by q-value if all content-types are fully defined", () async {
    // ignore: unawaited_futures
    getWithTypes(client, [
      "text/plain; q=0.4",
      "text/html; q=0.8",
      "application/json; charset=utf-8"
    ]);
    request = Request(await server.first);
    expect(
        request.acceptableContentTypes.first.primaryType == "application" &&
            request.acceptableContentTypes.first.subType == "json",
        true);
    expect(
        request.acceptableContentTypes[1].primaryType == "text" &&
            request.acceptableContentTypes[1].subType == "html",
        true);
    expect(
        request.acceptableContentTypes.last.primaryType == "text" &&
            request.acceptableContentTypes.last.subType == "plain",
        true);
    expect(request.acceptsContentType(ContentType.json), true);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.text), true);
    expect(request.acceptsContentType(ContentType.binary), false);
  });
}

Future getWithTypes(HttpClient client, List<String> contentTypeStrings) async {
  var req = await client.openUrl("GET", Uri.parse("http://localhost:8123"));
  if (contentTypeStrings != null) {
    if (contentTypeStrings.isEmpty) {
      req.headers.set(HttpHeaders.acceptHeader, "");
    } else {
      req.headers.add(HttpHeaders.acceptHeader, contentTypeStrings.join(", "));
    }
  }

  var response = await req.close();
  return response.drain();
}
