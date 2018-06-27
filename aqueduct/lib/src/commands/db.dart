import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/db/schema/migration_source.dart';
import 'package:safe_config/safe_config.dart';
import 'package:isolate_executor/isolate_executor.dart';
import '../db/db.dart';
import 'base.dart';
import 'db_generate.dart';
import 'db_show_migrations.dart';
import 'db_upgrade.dart';
import 'db_validate.dart';
import 'db_version.dart';
import 'db_schema.dart';
import 'scripts/schema_builder.dart';

class CLIDatabase extends CLICommand {
  CLIDatabase() {
    registerCommand(new CLIDatabaseUpgrade());
    registerCommand(new CLIDatabaseGenerate());
    registerCommand(new CLIDatabaseShowMigrations());
    registerCommand(new CLIDatabaseValidate());
    registerCommand(new CLIDatabaseVersion());
    registerCommand(new CLIDatabaseSchema());
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

abstract class CLIDatabaseManagingCommand extends CLICommand with CLIProject {
  CLIDatabaseManagingCommand() {
    options
      ..addOption("migration-directory",
          help:
              "The directory where migration files are stored. Relative paths are relative to the application-directory.",
          defaultsTo: "migrations");
  }

  Directory get migrationDirectory {
    final dir = new Directory(decode("migration-directory")).absolute;

    if (!dir.existsSync()) {
      dir.createSync();
    }
    return dir;
  }

  List<MigrationSource> get projectMigrations {
    try {
      final pattern = new RegExp(r"^[0-9]+[_a-zA-Z0-9]*\.migration\.dart$");
      final sources = migrationDirectory
        .listSync()
        .where((fse)
      => fse is File && pattern.hasMatch(fse.uri.pathSegments.last))
        .map((fse)
      => new MigrationSource.fromFile(fse.uri))
        .toList();

      sources.sort((s1, s2)
      => s1.versionNumber.compareTo(s2.versionNumber));

      return sources;
    } on StateError catch (e) {
      throw new CLIException(e.message);
    }
  }

  Future<Schema> schemaByApplyingMigrationSources(List<MigrationSource> sources, {Schema fromSchema}) async {
    fromSchema ??= new Schema.empty();

    if (sources.isNotEmpty) {
      displayProgress("Replaying versions: ${sources.map((f)
      => f.versionNumber.toString()).join(", ")}...");
    }

    final schemaMap = await IsolateExecutor.executeWithType(SchemaBuilderExecutable,
        packageConfigURI: packageConfigUri,
        imports: SchemaBuilderExecutable.imports,
        additionalContents: MigrationSource.combine(sources),
        message: SchemaBuilderExecutable.createMessage(sources, fromSchema),
        logHandler: displayProgress);

    return new Schema.fromMap(schemaMap as Map<String, dynamic>);
  }
}

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
