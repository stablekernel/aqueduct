import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:yaml/yaml.dart';

import '../http/http.dart';
import '../application/application.dart';
import '../utilities/source_generator.dart';
import 'base.dart';
import 'document_serve.dart';

abstract class CLIDocumentOptions implements CLICommand {
  String get title => values["title"];

  String get apiDescription => values["description"];

  String get apiVersion => values["api-version"];

  String get termsOfServiceURL => values["tos"];

  String get contactEmail => values["contact-email"];

  String get contactName => values["contact-name"];

  String get contactURL => values["contact-url"];

  String get licenseURL => values["license-url"];

  String get licenseName => values["license-name"];

  String get configurationPath => values["config-path"];

  List<Uri> get hosts {
    List<String> hostValues = values["host"] ?? ["http://localhost:8888"];
    return hostValues.map((str) {
      var uri = Uri.parse(str);
      if (uri == null) {
        throw new CLIException("Invalid Host Option",
            instructions: ["Host names must identify scheme, host and port. Example: https://api.myapp.com:8000"]);
      }

      return uri;
    }).toList();
  }

  void addDocumentConfigurationOptions() {
    options
      ..addOption("config-path",
          abbr: "c",
          help:
              "The path to a configuration file that this application needs to initialize resources for the purpose of documenting its API.",
          defaultsTo: "config.src.yaml")
      ..addOption("title", help: "API Docs: Title")
      ..addOption("description", help: "API Docs: Description")
      ..addOption("api-version", help: "API Docs: Version")
      ..addOption("tos", help: "API Docs: Terms of Service URL")
      ..addOption("contact-email", help: "API Docs: Contact Email")
      ..addOption("contact-name", help: "API Docs: Contact Name")
      ..addOption("contact-url", help: "API Docs: Contact URL")
      ..addOption("license-url", help: "API Docs: License URL")
      ..addOption("license-name", help: "API Docs: License Name")
      ..addMultiOption("host",
          help: "Scheme, host and port for available instances.", valueHelp: "https://api.myapp.com:8000");
  }

  Future<Map<String, dynamic>> documentProject(Uri projectDirectory, String libraryName, File pubspecFile) {
    var generator = new SourceGenerator((List<String> args, Map<String, dynamic> values) async {
      var config = new ApplicationOptions()..configurationFilePath = values["configPath"];

      var document = await Application.document(ApplicationChannel.defaultType, config, loadYaml(values["pubspec"]));

      document.servers = (values["hosts"] as List<Uri>)?.map((uri) => new APIServerDescription(uri))?.toList() ?? [];
      if (values["title"] != null) {
        document.info ??= new APIInfo.empty();
        document.info.title = values["title"];
      }
      if (values["description"] != null) {
        document.info ??= new APIInfo.empty();
        document.info.description = values["description"];
      }
      if (values["version"] != null) {
        document.info ??= new APIInfo.empty();
        document.info.version = values["version"];
      }
      if (values["termsOfServiceURL"] != null) {
        document.info ??= new APIInfo.empty();
        document.info.termsOfServiceURL = Uri.parse(values["termsOfServiceURL"]);
      }
      if (values["contactEmail"] != null) {
        document.info ??= new APIInfo.empty();
        document.info.contact ??= new APIContact.empty();
        document.info.contact.email = values["contactEmail"];
      }
      if (values["contactName"] != null) {
        document.info ??= new APIInfo.empty();
        document.info.contact ??= new APIContact.empty();
        document.info.contact.name = values["contactName"];
      }
      if (values["contactURL"] != null) {
        document.info ??= new APIInfo.empty();
        document.info.contact ??= new APIContact.empty();
        document.info.contact.url = Uri.parse(values["contactURL"]);
      }
      if (values["licenseURL"] != null) {
        document.info ??= new APIInfo.empty();
        document.info.license ??= new APILicense.empty();
        document.info.license.url = Uri.parse(values["licenseURL"]);
      }
      if (values["licenseName"] != null) {
        document.info ??= new APIInfo.empty();
        document.info.license ??= new APILicense.empty();
        document.info.license.name = values["licenseName"];
      }

      return document.asMap();
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName/$libraryName.dart",
      "dart:isolate",
      "dart:io",
      "package:yaml/yaml.dart",
      "dart:mirrors",
      "dart:async",
      "dart:convert"
    ]);

    final variables = {
      "pubspec": pubspecFile.readAsStringSync(),
      "hosts": hosts,
      "configPath": configurationPath,
      "title": title,
      "description": apiDescription,
      "version": apiVersion,
      "termsOfServiceURL": termsOfServiceURL,
      "contactEmail": contactEmail,
      "contactName": contactName,
      "contactURL": contactURL,
      "licenseURL": licenseURL,
      "licenseName": licenseName
    };

    var executor = new IsolateExecutor(generator, [libraryName],
        message: variables, packageConfigURI: projectDirectory.resolve(".packages"));

    return executor.execute() as Future<Map<String, dynamic>>;
  }
}

class CLIDocument extends CLICommand with CLIProject, CLIDocumentOptions {
  CLIDocument() {
    addDocumentConfigurationOptions();
    registerCommand(new CLIDocumentServe());
  }

  @override
  Future<int> handle() async {
    var documentMap = await documentProject(projectDirectory.uri, libraryName, projectSpecificationFile);

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
