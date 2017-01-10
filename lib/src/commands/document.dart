import 'dart:async';
import 'dart:io';
import 'dart:convert';

import '../http/http.dart';
import '../application/application.dart';
import '../utilities/source_generator.dart';
import 'base.dart';

/// Used internally.
class CLIDocument extends CLICommand with CLIProject {
  CLIDocument() {
    options
      ..addOption("config-path",
          abbr: "c",
          help:
          "The path to a configuration file. This file is available in the ApplicationConfiguration "
              "for a RequestSink to use to read application-specific configuration values. Relative paths are relative to [directory].",
          defaultsTo: "config.yaml.src")
      ..addOption("host", allowMultiple: true,
          help: "Scheme, host and port for available instances.",
          valueHelp: "https://api.myapp.com:8000");
  }

  List<Uri> get hosts {
    List<String> hostValues = values["host"] ?? ["http://localhost:8080"];
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

  Future<int> handle() async {
    print("${await documentProject()}");
    return 0;
  }

  Future<String> documentProject() async {
    var generator = new SourceGenerator(
        (List<String> args, Map<String, dynamic> values) async {
          var resolver = new PackagePathResolver(".packages");
          var document = await Application.document(
              RequestSink.defaultSinkType, new ApplicationConfiguration(), resolver);

          document.hosts = (values["hosts"] as List<String>)
              ?.map((hostString) => new APIHost.fromURI(Uri.parse((hostString))))
              ?.toList();

          document.info.title = values["title"] ?? "Aqueduct App";
          document.info.description = values["description"] ?? "An Aqueduct App";
          document.info.version = values["version"] ?? "1.0";
          document.info.termsOfServiceURL = values["termsOfServiceURL"] ?? "";
          document.info.contact.email = values["contactEmail"];
          document.info.contact.name = values["contactName"];
          document.info.contact.url = values["contactURL"];
          document.info.license.url = values["licenseURL"];
          document.info.license.name = values["licenseName"];


          return JSON.encode(document.asMap());
        }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName/$libraryName.dart",
      "dart:isolate",
      "dart:mirrors",
      "dart:async",
      "dart:convert"
    ]);

    var executor = new IsolateExecutor(generator, [libraryName],
        packageConfigURI: projectDirectory.uri.resolve(".packages"));
    var contents = await executor.execute(projectDirectory.uri);

    return contents;
  }

  String get name {
    return "document";
  }

  String get description {
    return "Generates an OpenAPI specification of an application.";
  }
}
