import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/cli/metadata.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/db/persistent_store/persistent_store.dart';
import 'package:safe_config/safe_config.dart';
import 'package:aqueduct/src/cli/command.dart';

abstract class CLIDatabaseConnectingCommand implements CLICommand, CLIProject {
  static const String flavorPostgreSQL = "postgres";
  static const String flavorMySql = "mysql";

  DatabaseConfigurationExt connectedDatabase;

  @Flag("use-ssl",
      help: "Whether or not the database connection should use SSL",
      defaultsTo: false)
  bool get useSSL => decode("use-ssl");

  @Option("connect",
      abbr: "c",
      help:
          "A database connection URI string. If this option is set, database-config is ignored.",
      valueHelp: "[postgres|mysql]://user:password@localhost:port/databaseName")
  String get databaseConnectionString => decode("connect");

  @Option("flavor",
      abbr: "f",
      help: "The database driver flavor to use.",
      defaultsTo: "postgres",
      allowed: ["postgres", "mysql"])
  String get databaseFlavor {
    if (_databaseFlavor != null) {
      return _databaseFlavor;
    }
    return decode("flavor");
    // return _databaseFlavor;
  }

  String _databaseFlavor;

  @Option("database-config",
      help:
          "A configuration file that provides connection information for the database. "
          "Paths are relative to project directory. If the connect option is set, this value is ignored. "
          "See 'aqueduct db -h' for details.",
      defaultsTo: "database.yaml")
  File get databaseConfigurationFile =>
      fileInProjectDirectory(decode("database-config"));

  PersistentStore _persistentStore;

  PersistentStore get persistentStore {
    if (_persistentStore != null) {
      return _persistentStore;
    }

    if (decode("flavor") == null) {
      throw CLIException("No database flavor selected. See --flavor.");
    }

    if (databaseFlavor == flavorPostgreSQL || databaseFlavor == flavorMySql) {
      if (databaseConnectionString != null) {
        try {
          connectedDatabase = DatabaseConfigurationExt();
          connectedDatabase.decode(databaseConnectionString);
        } catch (_) {
          throw CLIException("Invalid database configuration.", instructions: [
            "Invalid connection string was: $databaseConnectionString",
            "Expected format:               database://user:password@host:port/databaseName"
          ]);
        }
      } else {
        if (!databaseConfigurationFile.existsSync()) {
          throw CLIException("No database configuration file found.",
              instructions: [
                "Expected file at: ${databaseConfigurationFile.path}.",
                "See --connect and --database-config. If not using --connect, "
                    "this tool expects a YAML configuration file with the following format:\n$_dbConfigFormat"
              ]);
        }

        try {
          connectedDatabase =
              DatabaseConfigurationExt.fromFile(databaseConfigurationFile);
        } catch (_) {
          throw CLIException("Invalid database configuration.", instructions: [
            "File located at ${databaseConfigurationFile.path}.",
            "See --connect and --database-config. If not using --connect, "
                "this tool expects a YAML configuration file with the following format:\n$_dbConfigFormat"
          ]);
        }
      }
      if (databaseFlavor != connectedDatabase.schema) {
        _databaseFlavor = connectedDatabase.schema;
      }
      PersistentStoreConnection connection =
          PersistentStoreConnection.fromConfig(
              connectedDatabase.schema, connectedDatabase);
      return connection.persistentStore;
    }

    throw CLIException("Invalid flavor $databaseFlavor");
  }

  @override
  Future cleanup() async {
    return _persistentStore?.close();
  }

  String get _dbConfigFormat {
    return "\n\tschema: [postgres|mysql]\n\tusername: username\n\tpassword: password\n\thost: host\n\tport: port\n\tdatabaseName: name\n";
  }
}

class DatabaseConfigurationExt extends DatabaseConfiguration {
  DatabaseConfigurationExt() : super();

  DatabaseConfigurationExt.fromFile(File file) : super.fromFile(file);

  DatabaseConfigurationExt.fromString(String yaml) : super.fromString(yaml);

  DatabaseConfigurationExt.fromMap(Map<dynamic, dynamic> yaml)
      : super.fromMap(yaml);

  @optionalConfiguration
  String schema;

  @override
  void decode(dynamic value) {
    super.decode(value);
    if (value is String) {
      var uri = Uri.parse(value);
      schema = uri.scheme;
    }
  }
}
