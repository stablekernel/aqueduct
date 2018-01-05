import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../http/http.dart';

import 'base.dart';
import 'document.dart';

/// Used internally.
class CLIDocumentServe extends CLICommand with CLIProject, CLIDocumentOptions {
  CLIDocumentServe() {
    addDocumentConfigurationOptions();

    options..addOption("port", abbr: "p", help: "Port to listen on", defaultsTo: "8111");
  }

  int get port => int.parse(values["port"]);

  Router _router = new Router();

  Directory get _hostedDirectory => new Directory.fromUri(projectDirectory.uri.resolve(".aqueduct_spec"));
  HttpServer _server;

  @override
  Future<int> handle() async {
    var onComplete = new Completer();
    ProcessSignal.SIGINT.watch().listen((_) {
      onComplete.complete();
    });

    await _build();

    _server = await _listen();

    displayInfo("Document server listening on http://${_server.address.host}:${_server.port}/.",
        color: CLIColor.boldGreen);
    displayProgress("Use Ctrl-C (SIGINT) to stop running the server.");

    await onComplete.future;

    return 0;
  }

  @override
  Future cleanup() async {
    await _server?.close();
    _hostedDirectory.deleteSync(recursive: true);
  }

  Future<HttpServer> _listen() async {
    var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, port);

    var fileController = new HTTPFileController(_hostedDirectory.uri.path)
      ..addCachePolicy(new HTTPCachePolicy(requireConditionalRequest: true), (p) => p.endsWith(".html"))
      ..addCachePolicy(new HTTPCachePolicy(requireConditionalRequest: true), (p) => p.endsWith(".json"))
      ..addCachePolicy(new HTTPCachePolicy(expirationFromNow: new Duration(days: 300)), (p) => true)
      ..logger.onRecord.listen((rec) {
        print("${rec.message} ${rec.stackTrace ?? ""}");
      });

    _router.route("/*").link(() => fileController);
    _router.prepare();

    server.map((req) => new Request(req)).listen((req) {
      _router.receive(req);
    });

    return server;
  }

  Future _build() async {
    _hostedDirectory.createSync();
    var documentJSON = JSON.encode(await documentProject(projectDirectory.uri, libraryName));

    var jsonSpecFile = new File.fromUri(_hostedDirectory.uri.resolve("swagger.json"));
    jsonSpecFile.writeAsStringSync(documentJSON);

    var htmlFile = new File.fromUri(_hostedDirectory.uri.resolve("index.html"));
    htmlFile.writeAsStringSync(_htmlSource);
  }

  String get _htmlSource {
    return """
<!DOCTYPE html>
<html>
  <head>
    <title>ReDoc</title>
    <!-- needed for adaptive design -->
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body {
        margin: 0;
        padding: 0;
      }
    </style>
  </head>
  <body>
    <redoc spec-url='swagger.json'></redoc>
    <script src="https://rebilly.github.io/ReDoc/releases/latest/redoc.min.js"> </script>
  </body>
</html>    
    """;
  }

  @override
  String get name {
    return "serve";
  }

  @override
  String get description {
    return "Serves an OpenAPI specification web page.";
  }

  @override
  String get detailedDescription {
    return "This tool will start an HTTP server that serves an API reference web page. See `aqueduct document --help` for configuration options.";
  }
}
