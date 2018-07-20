import 'dart:async';

import 'package:aqueduct/src/cli/commands/auth_add_client.dart';
import 'package:aqueduct/src/cli/commands/auth_scope.dart';
import 'package:aqueduct/src/cli/command.dart';

class CLIAuth extends CLICommand {
  CLIAuth() {
    registerCommand(CLIAuthAddClient());
    registerCommand(CLIAuthScopeClient());
  }

  @override
  Future<int> handle() async {
    printHelp(parentCommandName: "aqueduct");
    return 0;
  }

  @override
  Future cleanup() async {}

  @override
  String get name {
    return "auth";
  }

  @override
  String get description {
    return "A tool for adding OAuth 2.0 clients to a database using the managed_auth package.";
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
}
