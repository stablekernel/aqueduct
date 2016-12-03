import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:args/args.dart';

main(List<String> args) async {
  var templateCreator = new CLITemplateCreator();
  var migrationRunner = new CLIMigrationRunner();
  var setupCommand = new CLISetup();

  var totalParser = new ArgParser(allowTrailingOptions: true)
    ..addCommand("create", templateCreator.options)
    ..addCommand("db", migrationRunner.options)
    ..addCommand("setup", setupCommand.options)
    ..addFlag("help",
        abbr: "h", negatable: false, help: "Shows this documentation");

  var values = totalParser.parse(args);

  if (values.command == null) {
    print(
        "Invalid command, options are: ${totalParser.commands.keys.join(", ")}");
    exitCode = 1;
    return;
  } else if (values.command.name == "create") {
    exitCode = await templateCreator.process(values.command);
    return;
  } else if (values.command.name == "db") {
    exitCode = await migrationRunner.process(values.command);
    return;
  } else if (values.command.name == "setup") {
    exitCode = await setupCommand.process(values.command);
    return;
  }

  print(
      "Invalid command, options are: ${totalParser.commands.keys.join(", ")}");
  exitCode = 1;
}
