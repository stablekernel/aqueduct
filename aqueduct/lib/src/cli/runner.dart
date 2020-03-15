import 'dart:async';

import 'package:aqueduct/src/cli/commands/auth.dart';
import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/commands/build.dart';
import 'package:aqueduct/src/cli/commands/create.dart';
import 'package:aqueduct/src/cli/commands/db.dart';
import 'package:aqueduct/src/cli/commands/document.dart';
import 'package:aqueduct/src/cli/commands/serve.dart';
import 'package:aqueduct/src/cli/commands/setup.dart';

class Runner extends CLICommand {
  Runner() {
    registerCommand(CLITemplateCreator());
    registerCommand(CLIDatabase());
    registerCommand(CLIServer());
    registerCommand(CLISetup());
    registerCommand(CLIAuth());
    registerCommand(CLIDocument());
    registerCommand(CLIBuild());
  }

  @override
  Future<int> handle() async {
    printHelp();
    return 0;
  }

  @override
  String get name {
    return "aqueduct";
  }

  @override
  String get description {
    return "Aqueduct is a tool for managing Aqueduct applications.";
  }
}
