import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:isolate_executor/isolate_executor.dart';

class GetSchemaExecutable extends Executable<Map<String, dynamic>> {
  GetSchemaExecutable(Map<String, dynamic> message) : super(message);

  @override
  Future<Map<String, dynamic>> execute() async {
    var dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    var schema = Schema.fromDataModel(dataModel);
    return schema.asMap();
  }

  static List<String> importsForPackage(String packageName) => [
        "package:aqueduct/aqueduct.dart",
        "package:$packageName/$packageName.dart"
      ];
}
