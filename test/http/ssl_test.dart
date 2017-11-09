import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:io';

void main() {
  group("SSL", () {
    Application app;

    tearDown(() async {
      await app?.stop();
    });

    test("Start with HTTPS", () async {
      var ciDirUri = new Directory("ci").uri;

      app = new Application<TestChannel>()
        ..options.certificateFilePath = ciDirUri.resolve("aqueduct.cert.pem").path
        ..options.privateKeyFilePath = ciDirUri.resolve("aqueduct.key.pem").path;

      await app.start(numberOfInstances: 1);

      var completer = new Completer();
      var socket = await SecureSocket.connect("localhost", 8081, onBadCertificate: (_) => true);
      var request = "GET /r HTTP/1.1\r\nConnection: close\r\nHost: localhost\r\n\r\n";
      socket.add(request.codeUnits);

      socket.listen((bytes) => completer.complete(bytes));
      var httpResult = new String.fromCharCodes(await completer.future);
      expect(httpResult, contains("200 OK"));
      await socket.close();
    });
  });
}

class TestChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/r").listen((r) async => new Response.ok(null));
    return router;
  }
}
