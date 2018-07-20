import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/mixins/database_connecting.dart';
import 'package:aqueduct/src/cli/mixins/database_managing.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';

/// Used internally.
class CLIDatabaseVersion extends CLICommand
    with CLIDatabaseManagingCommand, CLIProject, CLIDatabaseConnectingCommand {
  @override
  Future<int> handle() async {
    try {
      var current = await persistentStore.schemaVersion;
      displayInfo("Current version: $current");
      if (current == 0) {
        displayProgress("This database hasn't had a migration yet.");
      }
    } on SocketException catch (e) {
      displayError("Could not connect to database.");
      displayError("Reason: ${e.message}");
      displayProgress("Attempted database connection configuration:");
      displayProgress("  Host: ${connectedDatabase.host}");
      displayProgress("  Port: ${connectedDatabase.port}");
      displayProgress("  Username: ${connectedDatabase.username}");
      displayProgress("  Password: *** not echoed ***");
      displayProgress("  Database: ${connectedDatabase.databaseName}");

      return 1;
    }

    return 0;
  }

  @override
  Future cleanup() => persistentStore.close();

  @override
  String get name {
    return "get-version";
  }

  @override
  String get description {
    return "Shows the schema version of a database.";
  }
}
