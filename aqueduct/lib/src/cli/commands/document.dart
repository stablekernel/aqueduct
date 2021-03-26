import 'dart:async';
import 'dart:convert';

import 'package:aqueduct/src/cli/commands/oai_client.dart';
import 'package:aqueduct/src/cli/mixins/openapi_options.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/commands/document_serve.dart';
import 'package:aqueduct/src/cli/scripts/openapi_builder.dart';

class CLIDocument extends CLICommand with CLIProject, CLIDocumentOptions {
  CLIDocument() {
    registerCommand(CLIDocumentServe());
    registerCommand(CLIDocumentClient());
  }

  @override
  Future<int> handle() async {
    var documentMap = await documentProject(this, this);

    outputSink.writeln("${json.encode(documentMap)}");

    return 0;
  }

  @override
  String get name {
    return "document";
  }

  @override
  String get description {
    return "Generates an OpenAPI specification of an application.";
  }

  @override
  String get detailedDescription {
    return "This tool will generate an OpenAPI specification of an Aqueduct application. It operates by invoking Application.document. "
        "This method locates the ApplicationChannel subclass and invokes the first three phases of initialization:\n\n"
        "\tApplicationChannel.initializeApplication\n"
        "\tAppplicationChannel.prepare\n"
        "\tAppplicationChannel.entryPoint\n\n"
        "After these initialization methods are called, ApplicationChannel.document is invoked. Note that the full initialization process does not"
        " occur: Application.willStartReceivingRequests is not called because no web server is started. However, it is important that"
        " the first three steps of initialization can occur without error when generating documentation. This often requires having a"
        " valid configuration file (--config-path) when running this tool. The suggested approach is to use config.src.yaml as the configuration"
        " file for the document tool.";
  }
}
