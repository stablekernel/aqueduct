import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future main(List<String> args) async {
  // First try config.yaml, then config.yaml.src. If passing in config file, use that.
  var configuration = new WildfireConfiguration("config.yaml.src");
  configuration.database.isTemporary = true;

  var pipeline = new WildfirePipeline({
    WildfirePipeline.ConfigurationKey: configuration
  });

  pipeline.addRoutes();

  var resolver = new PackagePathResolver(".packages");
  var docs = pipeline.document(resolver);
  var document = new APIDocument()
    ..items = docs;

  var json = JSON.encode(document.asMap());
  var file = new File("swagger.json");
  var sink = file.openWrite();
  sink.write(json);
  await sink.close();
}