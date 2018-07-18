import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/src/cli/metadata.dart';
import 'package:aqueduct/src/cli/mixins/openapi_options.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/cli/running_process.dart';

import 'package:aqueduct/src/cli/command.dart';
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

    final fileController = HTTPFileController(
        _hostedDirectory.uri.toFilePath(windows: Platform.isWindows))
      ..addCachePolicy(const HTTPCachePolicy(requireConditionalRequest: true),
          (p) => p.endsWith(".html"))
      ..addCachePolicy(const HTTPCachePolicy(requireConditionalRequest: true),
          (p) => p.endsWith(".json"))
      ..addCachePolicy(
          HTTPCachePolicy(expirationFromNow: Duration(days: 300)), (p) => true)
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

    final documentJSON = json.encode(await documentProject(
        projectDirectory.uri, libraryName, projectSpecificationFile));
    final jsonSpecFile =
        File.fromUri(_hostedDirectory.uri.resolve("swagger.json"));
    jsonSpecFile.writeAsStringSync(documentJSON);

    var htmlFile = File.fromUri(_hostedDirectory.uri.resolve("index.html"));
    htmlFile.writeAsStringSync(_htmlSource);
  }

  String get _htmlSource {
    return """
<!DOCTYPE html>
<html>
  <head>
    <title>$packageName API Reference</title>
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
