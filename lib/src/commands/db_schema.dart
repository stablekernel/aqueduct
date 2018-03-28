import 'dart:async';
import 'dart:convert';

import '../db/db.dart';
import '../utilities/source_generator.dart';
import 'base.dart';
import 'db.dart';

class CLIDatabaseSchema extends CLIDatabaseManagingCommand {
  @override
  Future<int> handle() async {
    var map = await getSchema();
    if (isMachineOutput) {
      print("${json.encode(map)}");
    } else {
      var encoder = new JsonEncoder.withIndent("  ");
      print("${encoder.convert(map)}");
    }
    return 0;
  }

  @override
  String get name {
    return "schema";
  }

  @override
  String get description {
    return "Emits the data model of a project as JSON to stdout.";
  }

  Future<Map<String, dynamic>> getSchema() {
    var generator = new SourceGenerator((List<String> args, Map<String, dynamic> values) async {
      var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
      var schema = new Schema.fromDataModel(dataModel);
      return schema.asMap();
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName/$libraryName.dart",
      "dart:isolate",
      "dart:mirrors",
      "dart:async"
    ]);

    var executor = new IsolateExecutor(generator, [libraryName],
        message: {}, packageConfigURI: projectDirectory.uri.resolve(".packages"));

    return executor.execute() as Future<Map<String, dynamic>>;
  }
}
