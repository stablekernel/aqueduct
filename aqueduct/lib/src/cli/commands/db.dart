import 'dart:async';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/commands/db_generate.dart';
import 'package:aqueduct/src/cli/commands/db_show_migrations.dart';
import 'package:aqueduct/src/cli/commands/db_upgrade.dart';
import 'package:aqueduct/src/cli/commands/db_validate.dart';
import 'package:aqueduct/src/cli/commands/db_version.dart';
import 'package:aqueduct/src/cli/commands/db_schema.dart';

class CLIDatabase extends CLICommand {
  CLIDatabase() {
    registerCommand(CLIDatabaseUpgrade());
    registerCommand(CLIDatabaseGenerate());
    registerCommand(CLIDatabaseShowMigrations());
    registerCommand(CLIDatabaseValidate());
    registerCommand(CLIDatabaseVersion());
    registerCommand(CLIDatabaseSchema());
  }

  @override
  String get name {
    return "db";
  }

  @override
  String get description {
    return "Modifies, verifies and generates database schemas.";
  }

  @override
  String get detailedDescription {
    return "Some commands require connecting to a database to perform their action. These commands will "
        "have options for --connect and --database-config in their usage instructions."
        "You may either use a connection string (--connect) or a database configuration (--database-config) to provide "
        "connection details. The format of a connection string is: \n\n"
        "\tpostgres://username:password@host:port/databaseName\n\n"
        "A database configuration file is a YAML file with the following format:\n\n"
        "\tusername: \"user\"\n"
        "\tpassword: \"password\"\n"
        "\thost: \"host\"\n"
        "\tport: port\n"
        "\tdatabaseName: \"database\"";
  }

  @override
  Future<int> handle() async {
    printHelp();
    return 0;
  }
}
