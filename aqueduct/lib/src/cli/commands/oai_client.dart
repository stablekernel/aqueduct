import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/src/cli/mixins/openapi_options.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';

import 'package:aqueduct/src/cli/command.dart';

/// Used internally.
class CLIDocumentClient extends CLICommand with CLIProject, CLIDocumentOptions {
  @override
  Future<int> handle() async {
    final doc = await documentProject(
        projectDirectory.uri, libraryName, projectSpecificationFile);
    final source = _getHtmlSource(json.encode(doc));
    final file = File("client.html");
    file.writeAsStringSync(source);

    displayInfo(
        "OpenAPI client for application '${doc["info"]["title"]}' successfully created.",
        color: CLIColor.boldGreen);
    displayProgress(
        "Configured to connect to '${doc["servers"].first["url"]}'.");
    displayProgress("Open '${file.absolute.path}' in your browser.");

    return 0;
  }

  String _getHtmlSource(String spec) {
    return """
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">

<head>
    <meta charset="UTF-8">
    <title>Aqueduct OpenAPI Client</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@3.12.1/swagger-ui.css">
</head>

<body>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist@3.12.1/swagger-ui-standalone-preset.js"></script>
<script src="https://unpkg.com/swagger-ui-dist@3.12.1/swagger-ui-bundle.js"></script>
<script>
    window.onload = function() {       
        const ui = SwaggerUIBundle({
            spec: $spec,
            dom_id: '#swagger-ui',
            deepLinking: true,
            presets: [
                SwaggerUIBundle.presets.apis,
                SwaggerUIStandalonePreset
            ],
            plugins: [
                SwaggerUIBundle.plugins.DownloadUrl
            ],
            layout: "StandaloneLayout",
        })
        window.ui = ui
    }
</script>
</body>

</html>
    """;
  }

  @override
  String get name {
    return "client";
  }

  @override
  String get description {
    return "Generates an OpenAPI client web page.";
  }

  @override
  String get detailedDescription {
    return "The generated web page can be opened in a browser to execute requests against your application.";
  }
}
