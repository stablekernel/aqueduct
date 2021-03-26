import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/src/cli/metadata.dart';
import 'package:aqueduct/src/cli/mixins/openapi_options.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/cli/running_process.dart';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/scripts/openapi_builder.dart';
import 'package:aqueduct/src/http/http.dart';

/// Used internally.
class CLIDocumentServe extends CLICommand with CLIProject, CLIDocumentOptions {
  @Option("port", abbr: "p", help: "Port to listen on", defaultsTo: "8111")
  int get port => decode("port");

  @override
  StoppableProcess runningProcess;

  Directory get _hostedDirectory =>
      Directory.fromUri(projectDirectory.uri.resolve(".aqueduct_spec"));

  @override
  Future<int> handle() async {
    await _build();

    runningProcess = await _listen();

    return runningProcess.exitCode;
  }

  @override
  Future cleanup() async {
    if (_hostedDirectory.existsSync()) {
      _hostedDirectory.deleteSync(recursive: true);
    }
  }

  Future<StoppableProcess> _listen() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);

    final fileController = FileController(
        _hostedDirectory.uri.toFilePath(windows: Platform.isWindows))
      ..addCachePolicy(const CachePolicy(requireConditionalRequest: true),
          (p) => p.endsWith(".html"))
      ..addCachePolicy(const CachePolicy(requireConditionalRequest: true),
          (p) => p.endsWith(".json"))
      ..addCachePolicy(
          const CachePolicy(expirationFromNow: Duration(days: 300)), (p) => true)
      ..logger.onRecord.listen((rec) {
        outputSink.writeln("${rec.message} ${rec.stackTrace ?? ""}");
      });

    final router = Router();
    router.route("/*").link(() => fileController);
    router.didAddToChannel();

    server.map((req) => Request(req)).listen(router.receive);

    displayInfo(
        "Document server listening on http://${server.address.host}:${server.port}/.",
        color: CLIColor.boldGreen);
    displayProgress("Use Ctrl-C (SIGINT) to stop running the server.");

    return StoppableProcess((reason) async {
      displayInfo("Shutting down.");
      displayProgress("Reason: $reason");
      await server.close();
      displayProgress("Graceful shutdown complete.");
    });
  }

  Future _build() async {
    _hostedDirectory.createSync();

    final documentJSON = json.encode(await documentProject(this, this));
    final jsonSpecFile =
        File.fromUri(_hostedDirectory.uri.resolve("openapi.json"));
    jsonSpecFile.writeAsStringSync(documentJSON);

    var htmlFile = File.fromUri(_hostedDirectory.uri.resolve("index.html"));
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
    <link href="https://fonts.googleapis.com/css?family=Montserrat:300,400,700|Roboto:300,400,700" rel="stylesheet">

    <!--
    ReDoc doesn't change outer page styles
    -->
    <style>
      body {
        margin: 0;
        padding: 0;
      }
    </style>
  </head>
  <body>
    <redoc spec-url='openapi.json'></redoc>
    <script src="https://cdn.jsdelivr.net/npm/redoc@next/bundles/redoc.standalone.js"> </script>
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
