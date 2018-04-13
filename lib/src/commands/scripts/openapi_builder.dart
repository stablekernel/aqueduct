import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:isolate_executor/isolate_executor.dart';
import 'package:yaml/yaml.dart';

class OpenAPIBuilder extends Executable {
  OpenAPIBuilder(Map<String, dynamic> message)
      : pubspecContents = message["pubspec"],
        configPath = message["configPath"],
        title = message["title"],
        description = message["description"],
        version = message["version"],
        termsOfServiceURL = message["termsOfServiceURL"] != null ? Uri.parse(message["termsOfServiceURL"]) : null,
        contactEmail = message["contactEmail"],
        contactName = message["contactName"],
        contactURL = message["contactURL"] != null ? Uri.parse(message["contactURL"]) : null,
        licenseURL = message["licenseURL"] != null ? Uri.parse(message["licenseURL"]) : null,
        licenseName = message["licenseName"],
        hosts =
            (message["hosts"] as List<String>)?.map((uri) => new APIServerDescription(Uri.parse(uri)))?.toList() ?? [],
        super(message);

  final String pubspecContents;
  final String configPath;
  final String title;
  final String description;
  final String version;
  final Uri termsOfServiceURL;
  final String contactEmail;
  final String contactName;
  final Uri contactURL;
  final Uri licenseURL;
  final String licenseName;
  final List<APIServerDescription> hosts;

  @override
  Future<dynamic> execute() async {
    var config = new ApplicationOptions()..configurationFilePath = configPath;

    var document = await Application.document(ApplicationChannel.defaultType, config, loadYaml(pubspecContents));

    document.servers = hosts;
    if (title != null) {
      document.info ??= new APIInfo.empty();
      document.info.title = title;
    }
    if (description != null) {
      document.info ??= new APIInfo.empty();
      document.info.description = description;
    }
    if (version != null) {
      document.info ??= new APIInfo.empty();
      document.info.version = version;
    }
    if (termsOfServiceURL != null) {
      document.info ??= new APIInfo.empty();
      document.info.termsOfServiceURL = termsOfServiceURL;
    }
    if (contactEmail != null) {
      document.info ??= new APIInfo.empty();
      document.info.contact ??= new APIContact.empty();
      document.info.contact.email = contactEmail;
    }
    if (contactName != null) {
      document.info ??= new APIInfo.empty();
      document.info.contact ??= new APIContact.empty();
      document.info.contact.name = contactName;
    }
    if (contactURL != null) {
      document.info ??= new APIInfo.empty();
      document.info.contact ??= new APIContact.empty();
      document.info.contact.url = contactURL;
    }
    if (licenseURL != null) {
      document.info ??= new APIInfo.empty();
      document.info.license ??= new APILicense.empty();
      document.info.license.url = licenseURL;
    }
    if (licenseName != null) {
      document.info ??= new APIInfo.empty();
      document.info.license ??= new APILicense.empty();
      document.info.license.name = licenseName;
    }

    return document.asMap();
  }

  static List<String> importsForPackage(String packageName) => [
        "package:aqueduct/aqueduct.dart",
        "package:$packageName/$packageName.dart",
        "package:yaml/yaml.dart",
        "dart:convert",
        "dart:io"
      ];
}
