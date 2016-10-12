import 'dart:async';
import 'package:args/args.dart';
import 'package:aqueduct/aqueduct.dart';

Future<int> main(List<String> args) async {
  var templateCreator = new TemplateCreator();
  var migrationRunner = new MigrationRunner();
  var totalParser = new ArgParser(allowTrailingOptions: true)
    ..addCommand("create", templateCreator.options)
    ..addCommand("db", migrationRunner.options)
    ..addFlag("help", negatable: false, help: "Shows this documentation");

  var values = totalParser.parse(args);

  if (values.command == null) {
    print("Invalid command, options are: ${totalParser.commands.keys.join(", ")}");
    return -1;
  } else if (values.command.name == "create") {
    return await templateCreator.handle(values.command);
  } else if (values.command.name == "db") {
    return await migrationRunner.handle(values.command);
  }

  print("Invalid command, options are: ${totalParser.commands.keys.join(", ")}");
  return -1;
}
