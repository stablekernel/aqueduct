import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  ClientServer clientServer = ClientServer();

  setUp(() async {
    await clientServer.open();
  });

  tearDown(() async {
    await clientServer.close();
  });

  test("No accept header returns [], all are allowed", () async {
    final request = await clientServer.getWithTypes(null);
    expect(request.acceptableContentTypes, []);
    expect(request.acceptsContentType(ContentType.json), true);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.binary), true);
  });

  test("Empty Accept header returns [], all are allowed", () async {
    final request = await clientServer.getWithTypes([]);
    expect(request.acceptableContentTypes.isEmpty, true);
    expect(request.acceptsContentType(ContentType.json), true);
    expect(request.acceptsContentType(ContentType.html), true);
    expect(request.acceptsContentType(ContentType.binary), true);
  });

  test(
      "Two implicitly equal q-values order is defined by their position in request",
      () async {
    final request =
        await clientServer.getWithTypes(["text/plain", "text/html"]);
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
    final request = await clientServer
        .getWithTypes(["text/plain; q=1.0", "text/html; q=1.0"]);

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
    final request = await clientServer
        .getWithTypes(["text/plain; q=1.0", "text/html; q=1"]);
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
    final request = await clientServer.getWithTypes(["*/*", "text/html"]);
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
    final request = await clientServer.getWithTypes(["text/*", "text/html"]);
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
    final request = await clientServer.getWithTypes([
      "text/plain; q=0.4",
      "text/html; q=0.8",
      "application/json; charset=utf-8"
    ]);

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

class ClientServer {
  HttpServer server;
  HttpClient client;

  List<Request> _requests = [];

  Future open() async {
    client = HttpClient();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    server.map((r) => Request(r)).listen((r) {
      _requests.add(r);
      r.raw.response.statusCode = 200;
      r.raw.response.close();
    });
  }

  Future close() async {
    _requests = [];
    client.close(force: true);
    await server.close();
  }

  Future<Request> getWithTypes(List<String> contentTypeStrings) async {
    assert(_requests.isEmpty);

    var req = await client.openUrl("GET", Uri.parse("http://localhost:8123"));
    if (contentTypeStrings != null) {
      if (contentTypeStrings.isEmpty) {
        req.headers.set(HttpHeaders.acceptHeader, "");
      } else {
        req.headers
            .add(HttpHeaders.acceptHeader, contentTypeStrings.join(", "));
      }
    }

    var response = await req.close();
    await response.drain();

    return _requests.removeAt(0);
  }
}
