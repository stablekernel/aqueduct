import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/cli/mixins/database_managing.dart';
import 'package:aqueduct/src/db/persistent_store/persistent_store.dart';
import 'package:aqueduct/src/db/postgresql/postgresql_persistent_store.dart';
import 'package:safe_config/safe_config.dart';
import 'package:aqueduct/src/cli/command.dart';

abstract class CLIDatabaseConnectingCommand extends CLIDatabaseManagingCommand {
  static const String FlavorPostgreSQL = "postgres";

  CLIDatabaseConnectingCommand() {
    options
      ..addOption("name")
      ..addOption("flavor",
        abbr: "f", help: "The database driver flavor to use.", defaultsTo: "postgres", allowed: ["postgres"])
      ..addOption("connect",
        abbr: "c",
        help: "A database connection URI string. If this option is set, database-config is ignored.",
        valueHelp: "postgres://user:password@localhost:port/databaseName")
      ..addOption("database-config",
        help: "A configuration file that provides connection information for the database. "
          "Paths are relative to project directory. If the connect option is set, this value is ignored. "
          "See 'aqueduct db -h' for details.",
        defaultsTo: "database.yaml")
      ..addFlag("use-ssl", help: "Whether or not the database connection should use SSL", defaultsTo: false);
  }

  DatabaseConfiguration connectedDatabase;

  bool get useSSL => decode("use-ssl");

  String get databaseConnectionString => decode("connect");

  String get databaseFlavor => decode("flavor");

  File get databaseConfigurationFile => fileInProjectDirectory(decode("database-config"));

  PersistentStore _persistentStore;

  PersistentStore get persistentStore {
    if (_persistentStore != null) {
      return _persistentStore;
    }

    if (decode("flavor") == null) {
      throw new CLIException("No database flavor selected. See --flavor.");
    }

    if (databaseFlavor == FlavorPostgreSQL) {
      if (databaseConnectionString != null) {
        try {
          connectedDatabase = new DatabaseConfiguration();
          connectedDatabase.decode(databaseConnectionString);
        } catch (_) {
          throw new CLIException("Invalid database configuration.", instructions: [
            "Invalid connection string was: $databaseConnectionString",
            "Expected format:               database://user:password@host:port/databaseName"
          ]);
        }
      } else {
        if (!databaseConfigurationFile.existsSync()) {
          throw new CLIException("No database configuration file found.", instructions: [
            "Expected file at: ${databaseConfigurationFile.path}.",
            "See --connect and --database-config. If not using --connect, "
              "this tool expects a YAML configuration file with the following format:\n$_dbConfigFormat"
          ]);
        }

        try {
          connectedDatabase = new DatabaseConfiguration.fromFile(databaseConfigurationFile);
        } catch (_) {
          throw new CLIException("Invalid database configuration.", instructions: [
            "File located at ${databaseConfigurationFile.path}.",
            "See --connect and --database-config. If not using --connect, "
              "this tool expects a YAML configuration file with the following format:\n$_dbConfigFormat"
          ]);
        }
      }

      _persistentStore = new PostgreSQLPersistentStore(connectedDatabase.username, connectedDatabase.password,
        connectedDatabase.host, connectedDatabase.port, connectedDatabase.databaseName,
        useSSL: useSSL);
      return _persistentStore;
    }

    throw new CLIException("Invalid flavor $databaseFlavor");
  }

  @override
  Future cleanup() async {
    return _persistentStore?.close();
  }

  String get _dbConfigFormat {
    return "\n\tusername: username\n\tpassword: password\n\thost: host\n\tport: port\n\tdatabaseName: name\n";
  }
}
