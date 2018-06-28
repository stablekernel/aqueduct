import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/scripts/openapi_builder.dart';
import 'package:isolate_executor/isolate_executor.dart';

abstract class CLIDocumentOptions implements CLICommand {
  String get title => decode("title");

  String get apiDescription => decode("description");

  String get apiVersion => decode("api-version");

  String get termsOfServiceURL => decode("tos");

  String get contactEmail => decode("contact-email");

  String get contactName => decode("contact-name");

  String get contactURL => decode("contact-url");

  String get licenseURL => decode("license-url");

  String get licenseName => decode("license-name");

  String get configurationPath => decode("config-path");

  List<Uri> get hosts {
    List<String> hostValues = decode("host") ?? ["http://localhost:8888"];
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

  Future<Map<dynamic, dynamic>> documentProject(Uri projectDirectory, String libraryName, File pubspecFile) async {
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
    final result = await IsolateExecutor.executeWithType(OpenAPIBuilder,
      packageConfigURI: projectDirectory.resolve(".packages"),
      message: variables,
      imports: OpenAPIBuilder.importsForPackage(libraryName));
    return result as Map<dynamic, dynamic>;
  }
}