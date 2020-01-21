import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:isolate_executor/isolate_executor.dart';

class GetSchemaExecutable extends Executable<Map<String, dynamic>> {
  GetSchemaExecutable(Map<String, dynamic> message) : super(message);

  @override
  Future<Map<String, dynamic>> execute() async {
    try {
      var dataModel = ManagedDataModel.fromCurrentMirrorSystem();
      var schema = Schema.fromDataModel(dataModel);
      return schema.asMap();
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

Future<Schema> getProjectSchema(CLIProject project) async {
  final response = await IsolateExecutor.run(GetSchemaExecutable({}),
      imports: GetSchemaExecutable.importsForPackage(project.libraryName),
      packageConfigURI: project.packageConfigUri,
      logHandler: project.displayProgress);

  if (response.containsKey("error")) {
    throw CLIException(response["error"] as String);
  }

  return Schema.fromMap(response);
}
