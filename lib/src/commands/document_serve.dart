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

  String get _generatedDirectory => ".aqueduct_spec";

  @override
  Future<int> handle() async {
    await _build();

    var server = await _listen();
    displayInfo("Document server listening on http://${server.address.host}:${server.port}/.",
        color: CLIColor.boldGreen);
    displayProgress("Use Ctrl-C (SIGINT) to stop running the server.");

    return 0;
  }

  Future<HttpServer> _listen() async {
    var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, port);
    ProcessSignal.SIGINT.watch().listen((_) {
      cleanup();
      server.close();
      exit(0);
    });

    var fileController = new HTTPFileController(_generatedDirectory)
      ..addCachePolicy(new HTTPCachePolicy(requireConditionalRequest: true), (p) => p.endsWith(".html"))
      ..addCachePolicy(new HTTPCachePolicy(requireConditionalRequest: true), (p) => p.endsWith(".json"))
      ..addCachePolicy(new HTTPCachePolicy(expirationFromNow: new Duration(days: 300)), (p) => true)
      ..logger.onRecord.listen((rec) {
        print("${rec.message} ${rec.stackTrace ?? ""}");
      });

    _router.route("/*").pipe(fileController);
    _router.finalize();

    server.map((req) => new Request(req)).listen((req) {
      _router.receive(req);
    });

    return server;
  }

  Future _build() async {
    try {
      var directory = new Directory(_generatedDirectory);
      directory.createSync();
      var documentJSON = JSON.encode(await documentProject(projectDirectory.uri, libraryName));

      var jsonSpecFile = new File.fromUri(directory.uri.resolve("swagger.json"));
      jsonSpecFile.writeAsStringSync(documentJSON);

      var htmlFile = new File.fromUri(directory.uri.resolve("index.html"));
      htmlFile.writeAsStringSync(_htmlSource);
    } catch (e, st) {
      displayError("Failed to generate documentation");
      displayProgress("$e");
      if (showStacktrace) {
        displayProgress("$st");
      }
    }
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
