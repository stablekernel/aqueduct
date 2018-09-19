import 'dart:async';
import 'dart:convert';

import 'package:aqueduct/src/cli/command.dart';

class CLIDescribe extends CLICommand {
  CLIDescribe(this.rootCommand);

  final CLICommand rootCommand;

  @override
  Future<int> handle() async {
    final object = rootCommand.describe();
    outputSink.writeln(json.encode(object));
    return 0;
  }

  @override
  Future cleanup() async {}

  @override
  String get name {
    return "describe";
  }

  @override
  String get description {
    return "Prints a JSON document that describes the commands and arguments of this tool.";
  }
}
