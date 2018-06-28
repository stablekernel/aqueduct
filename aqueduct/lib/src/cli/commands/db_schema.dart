import 'dart:async';
import 'dart:convert';

import 'package:aqueduct/src/cli/mixins/database_managing.dart';
import 'package:aqueduct/src/cli/scripts/get_schema.dart';
import 'package:isolate_executor/isolate_executor.dart';

class CLIDatabaseSchema extends CLIDatabaseManagingCommand {
  @override
  Future<int> handle() async {
    var map = await getSchema();
    if (isMachineOutput) {
      outputSink.write("${json.encode(map)}");
    } else {
      var encoder = new JsonEncoder.withIndent("  ");
      outputSink.write("${encoder.convert(map)}");
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

  Future<dynamic> getSchema() {
    return IsolateExecutor.executeWithType(GetSchemaExecutable,
        packageConfigURI: packageConfigUri,
        imports: GetSchemaExecutable.importsForPackage(packageName),
        logHandler: displayProgress);
  }
}
