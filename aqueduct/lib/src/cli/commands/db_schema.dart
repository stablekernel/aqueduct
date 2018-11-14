import 'dart:async';
import 'dart:convert';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/mixins/database_managing.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/cli/scripts/get_schema.dart';

class CLIDatabaseSchema extends CLICommand
    with CLIDatabaseManagingCommand, CLIProject {
  @override
  Future<int> handle() async {
    var map = (await getProjectSchema(this)).asMap();
    if (isMachineOutput) {
      outputSink.write("${json.encode(map)}");
    } else {
      const encoder = JsonEncoder.withIndent("  ");
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
}
