import 'dart:async';
import 'dart:convert';

import '../http/http.dart';
import '../application/application.dart';
import '../utilities/source_generator.dart';
import 'base.dart';
import 'document_serve.dart';

abstract class CLIDocumentOptions implements CLICommand {
  String get title => values["title"];
  String get apiDescription => values["description"];
  String get version => values["version"];
  String get termsOfServiceURL => values["tos"];
  String get contactEmail => values["contact-email"];
  String get contactName => values["contact-name"];
  String get contactURL => values["contact-url"];
  String get licenseURL => values["license-url"];
  String get licenseName => values["license-name"];
  String get configurationPath => values["config-path"];
  List<Uri> get hosts {
    List<String> hostValues = values["host"] ?? ["http://localhost:8081"];
    return hostValues.map((str) {
      var uri = Uri.parse(str);
      if (uri == null) {
        throw new CLIException("Invalid Host Option", instructions: [
          "Host names must identify scheme, host and port. Example: https://api.myapp.com:8000"
        ]);
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
      ..addOption("title", help: "API Docs: Title", defaultsTo: "Aqueduct App")
      ..addOption("description",
          help: "API Docs: Description", defaultsTo: "An Aqueduct App")
      ..addOption("version", help: "API Docs: Version", defaultsTo: "1.0")
      ..addOption("tos", help: "API Docs: Terms of Service URL", defaultsTo: "")
      ..addOption("contact-email",
          help: "API Docs: Contact Email", defaultsTo: "")
      ..addOption("contact-name",
          help: "API Docs: Contact Name", defaultsTo: "")
      ..addOption("contact-url", help: "API Docs: Contact URL", defaultsTo: "")
      ..addOption("license-url", help: "API Docs: License URL", defaultsTo: "")
      ..addOption("license-name",
          help: "API Docs: License Name", defaultsTo: "")
      ..addOption("host",
          allowMultiple: true,
          help: "Scheme, host and port for available instances.",
          valueHelp: "https://api.myapp.com:8000");
  }

  Future<Map<String, dynamic>> documentProject(Uri projectDirectory, String libraryName) {
    var generator = new SourceGenerator(
            (List<String> args, Map<String, dynamic> values) async {
          var resolver = new PackagePathResolver(".packages");
          var config = new ApplicationConfiguration()
            ..configurationFilePath = values["configPath"];

          var document = await Application.document(
              ApplicationChannel.defaultType, config, resolver);

          document.hosts = (values["hosts"] as List<String>)
              ?.map((hostString) => new APIHost.fromURI(Uri.parse((hostString))))
              ?.toList();

          document.info.title = values["title"];
          document.info.description = values["apiDescription"];
          document.info.version = values["version"];
          document.info.termsOfServiceURL = values["termsOfServiceURL"];
          document.info.contact.email = values["contactEmail"];
          document.info.contact.name = values["contactName"];
          document.info.contact.url = values["contactURL"];
          document.info.license.url = values["licenseURL"];
          document.info.license.name = values["licenseName"];

          return document.asMap();
        }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName/$libraryName.dart",
      "dart:isolate",
      "dart:mirrors",
      "dart:async",
      "dart:convert"
    ]);

    var executor = new IsolateExecutor(generator, [libraryName],
        message: {
          "configPath": configurationPath,
          "title": title,
          "apiDescription": apiDescription,
          "version": version,
          "termsOfServiceURL": termsOfServiceURL,
          "contactEmail": contactEmail,
          "contactName": contactName,
          "contactURL": contactURL,
          "licenseURL": licenseURL,
          "licenseName": licenseName
        },
        packageConfigURI: projectDirectory.resolve(".packages"));

    return executor.execute(projectDirectory) as Future<Map<String, dynamic>>;
  }
}

class CLIDocument extends CLICommand with CLIProject, CLIDocumentOptions {
  CLIDocument() {
    addDocumentConfigurationOptions();
    registerCommand(new CLIDocumentServe());
  }
  
  @override
  Future<int> handle() async {
    try {
      var documentMap = await documentProject(projectDirectory.uri, libraryName);
      print("${JSON.encode(documentMap)}");
    } catch (e, st) {
      displayError("Failed to generate documentation");
      displayProgress("$e");
      if (showStacktrace) {
        displayProgress("$st");
      }

      return -1;
    }
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
        "\tAppplicationChannel.willOpej\n"
        "\tAppplicationChannel.entryPoint\n\n"
        "After these initialization methods are called, ApplicationChannel.document is invoked. Note that the full initialization process does not"
        " occur: Application.didOpen is not called because no web server is started. However, it is important that"
        " the first three steps of initialization can occur without error when generating documentation. This often requires having a"
        " valid configuration file (--config-path) when running this tool. The suggested approach is to use config.src.yaml as the configuration"
        " file for the document tool. The flag 'isDocumenting' will be set to true in ApplicationConfiguration.";
  }
}
