import 'dart:io';
import 'dart:async';

import 'package:aqueduct/executable.dart';

main(List<String> args) async {
  var runner = new Runner();
  var values = runner.options.parse(args);
  exitCode = await runner.process(values);
}

class Runner extends CLICommand {
  Runner() {
    registerCommand(new CLITemplateCreator());
    registerCommand(new CLIDatabase());
    registerCommand(new CLIServer());
    registerCommand(new CLISetup());
  }

  Future<int> handle() async {
    printHelp();
    return 0;
  }

  String get name {
    return "aqueduct";
  }

  String get description {
    return "Aqueduct is a tool for managing Aqueduct applications.";
  }
}