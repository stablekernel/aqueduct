import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:isolate_executor/isolate_executor.dart';

class MigrationBuilderExecutable extends Executable {
  MigrationBuilderExecutable(Map<String, dynamic> message)
      : inputSchema = new Schema.fromMap(message["inputSchema"]),
        versionTag = message["versionTag"],
        super(message);

  final int versionTag;
  final Schema inputSchema;

  @override
  Future<dynamic> execute() async {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var schema = new Schema.fromDataModel(dataModel);
    var changeList = <String>[];

    final source = Migration.sourceForSchemaUpgrade(inputSchema, schema, versionTag, changeList: changeList);
    return {
      "source": source,
      "tablesEvaluated": dataModel.entities.map((e) => e.name).toList(),
      "changeList": changeList
    };
  }

  static List<String> importsForPackage(String packageName) =>
      ["package:aqueduct/aqueduct.dart", "package:$packageName/$packageName.dart"];

  static Map<String, dynamic> createMessage(int versionTag, Schema inputSchema) {
    return {"inputSchema": inputSchema.asMap(), "versionTag": versionTag};
  }
}

class MigrationBuilderResult {
  MigrationBuilderResult.fromMap(Map<String, dynamic> result)
      : source = result["source"],
        tablesEvaluated = result["tablesEvaluated"],
        changeList = result["changeList"];

  final String source;
  final List<String> tablesEvaluated;
  final List<String> changeList;
}
