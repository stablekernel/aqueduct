import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:isolate_executor/isolate_executor.dart';

class MigrationBuilderExecutable extends Executable<Map<String, dynamic>> {
  MigrationBuilderExecutable(Map<String, dynamic> message)
      : inputSchema =
            Schema.fromMap(message["inputSchema"] as Map<String, dynamic>),
        versionTag = message["versionTag"] as int,
        super(message);

  MigrationBuilderExecutable.input(this.inputSchema, this.versionTag)
      : super({"inputSchema": inputSchema.asMap(), "versionTag": versionTag});

  final int versionTag;
  final Schema inputSchema;

  @override
  Future<Map<String, dynamic>> execute() async {
    try {
      var dataModel = ManagedDataModel.fromCurrentMirrorSystem();
      var schema = Schema.fromDataModel(dataModel);
      var changeList = <String>[];

      final source = Migration.sourceForSchemaUpgrade(
          inputSchema, schema, versionTag,
          changeList: changeList);
      return {
        "source": source,
        "tablesEvaluated": dataModel.entities.map((e) => e.name).toList(),
        "changeList": changeList
      };
    } on SchemaException catch (e) {
      return {"error": e.message};
    } on ManagedDataModelError catch (e) {
      return {"error": e.message};
    }
  }

  static List<String> importsForPackage(String packageName) => [
        "package:aqueduct/aqueduct.dart",
        "package:$packageName/$packageName.dart",
        "package:runtime/runtime.dart"
      ];
}

class MigrationBuilderResult {
  MigrationBuilderResult.fromMap(Map<String, dynamic> result)
      : source = result["source"] as String,
        tablesEvaluated = result["tablesEvaluated"] as List<String>,
        changeList = result["changeList"] as List<String>;

  final String source;
  final List<String> tablesEvaluated;
  final List<String> changeList;
}

Future<MigrationBuilderResult> generateMigrationFileForProject(
    CLIProject project, Schema initialSchema, int inputVersion) async {
  final resultMap = await IsolateExecutor.run(
      MigrationBuilderExecutable.input(initialSchema, inputVersion),
      packageConfigURI: project.packageConfigUri,
      imports:
          MigrationBuilderExecutable.importsForPackage(project.packageName),
      logHandler: project.displayProgress);

  if (resultMap.containsKey("error")) {
    throw CLIException(resultMap["error"] as String);
  }

  return MigrationBuilderResult.fromMap(resultMap);
}
