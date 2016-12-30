import 'dart:async';
import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:safe_config/safe_config.dart';
import 'package:args/args.dart';

import 'cli_command.dart';
import '../db/db.dart';

/// Used internally.
class CLIDatabase extends CLICommand {
  static const String FlavorPostgreSQL = "postgres";

  MigrationExecutor executor;
  ArgParser options = new ArgParser(allowTrailingOptions: false)
    ..addOption("flavor",
        abbr: "f",
        help: "The database driver flavor to use.",
        defaultsTo: "postgres",
        allowed: ["postgres"])
    ..addOption("connect", abbr: "c", help: "A database connection URI string, without the protocol/scheme. If this option is set, dbconfig is ignored.", valueHelp: "user:password@localhost:port/databaseName")
    ..addOption("dbconfig",
        abbr: "d",
        help:
            "A configuration file that provides connection information for the database. Paths are relative to migration-directory. If the connect option is set, this value is ignored.",
        defaultsTo: "migration.yaml")
    ..addOption("migration-directory",
        abbr: "m",
        help:
            "The directory where migration files are stored. Relative paths are relative to the application-directory.",
        defaultsTo: "migrations")
    ..addOption("application-directory",
        abbr: "a",
        help:
            "An Aqueduct application project directory. This directory must contain a pubspec.yaml file. Relative paths are relative to the current working directory.",
        defaultsTo: Directory.current.path)
    ..addFlag("use-ssl",
        help: "Whether or not the database connection should use SSL", defaultsTo: false)
    ..addOption("library-name",
        abbr: "l",
        help:
            "The name of the application library file in the package, without the .dart suffix. This name is resolved according to the .packages mapping in the application-directory. By default, this value will be the name of the application package defined in pubspec.yaml. Thus, a package with the name 'foobar' will default to 'foobar', and the library file is then 'package:foobar/foobar.dart'.")
    ..addCommand("validate")
    ..addCommand("upgrade")
    ..addCommand("generate")
    ..addCommand("list-versions")
    ..addCommand("version")
    ..addFlag("help",
        abbr: "h", negatable: false, help: "Shows this documentation");

  String get _dbConfigFormat {
    return "\n\tusername: username\n\tpassword: password\n\thost: host\n\tport: port\n\tdatabaseName: name\n";
  }

  bool get useSSL => values["use-ssl"];
  String get databaseConnectionString => values["connect"];
  String get databaseFlavor => values["flavor"];
  String get databaseConfig => values["dbconfig"];
  String get migrationDirectory => values["migration-directory"];
  String get applicationDirectory => values["application-directory"];
  String get libraryName => values["library-name"];
  bool get helpMeItsScary => values["help"];
  ArgResults get command => values.command;

  Future<int> handle() async {
    var projectURI = new Uri.directory(applicationDirectory);
    if (!projectURI.isAbsolute) {
      projectURI = Directory.current.uri.resolveUri(projectURI);
    }

    var packageName = getPackageNameFromDirectoryURI(projectURI);
    var libraryPath = "$packageName/${libraryName ?? packageName}.dart";

    Uri migrationDirectoryURI =
        new Uri.directory(migrationDirectory);
    if (!migrationDirectoryURI.isAbsolute) {
      migrationDirectoryURI = projectURI.resolveUri(migrationDirectoryURI);

      var directory = new Directory.fromUri(migrationDirectoryURI);
      if (!directory.existsSync()) {
        directory.createSync();
      }
    }

    Uri dbConfigURI = new Uri.file(databaseConfig);
    if (!dbConfigURI.isAbsolute) {
      dbConfigURI = migrationDirectoryURI.resolveUri(dbConfigURI);
    }

    PersistentStore store = null;
    if (databaseFlavor == FlavorPostgreSQL) {
      var dbConfigFile = new File.fromUri(dbConfigURI);
      if (dbConfigFile.existsSync()) {
        var dbConfig = new DatabaseConnectionConfiguration();
        try {
          if (databaseConnectionString != null) {
            dbConfig.decode(databaseConnectionString);
          } else {
            var contents = dbConfigFile.readAsStringSync();
            var yaml = loadYaml(contents);
            dbConfig.readFromMap(yaml);
          }
        } catch (e) {
          displayError(
              "Invalid dbconfig. Expected $_dbConfigFormat\nat ${dbConfigURI}.");
          rethrow;
        }

        store = new PostgreSQLPersistentStore.fromConnectionInfo(
            dbConfig.username,
            dbConfig.password,
            dbConfig.host,
            dbConfig.port,
            dbConfig.databaseName,
            useSSL: useSSL);
      }
    } else {
      displayError("Invalid flavor ${databaseFlavor}\n\n${options.usage}");
      return -1;
    }

    executor = new MigrationExecutor(
        store, projectURI, libraryPath, migrationDirectoryURI);

    if (command?.name == "validate") {
      return await validate();
    } else if (command?.name == "list-versions") {
      return await listVersions();
    } else if (command?.name == "version") {
      return await printVersion();
    } else if (command?.name == "upgrade") {
      return await upgrade();
    } else if (command?.name == "generate") {
      return await generate();
    }

    displayError(
        "Invalid command, options for db are: ${options.commands.keys.join(", ")}");
    return -1;
  }

  Future<int> validate() async {
    try {
      await executor.validate();
      displayInfo(
          "Success! The migration files in ${executor.migrationFileDirectoryURI} will create a schema that matches the data model in ${executor.projectDirectoryPath}.");

      return 0;
    } catch (e) {
      displayError("Invalid migrations\n$e");
      return -1;
    }
  }

  Future<int> listVersions() async {
    var files = executor.migrationFiles.map((f) {
      var versionString =
          "${executor.versionNumberFromFile(f)}".padLeft(8, "0");
      return " $versionString | ${f.path}";
    }).join("\n");

    print(" Version  | Path");
    print("----------|-----------");
    print("$files");

    return 0;
  }

  Future<int> printVersion() async {
    if (executor.persistentStore == null) {
      displayError(_noDBConfigString);
      return -1;
    }

    try {
      var current = await executor.persistentStore.schemaVersion;
      displayInfo("Current version: $current");
    } catch (e) {
      displayError(
          "Could not determine schema version. Does database exist (with a version table) and can it be connected to?\n$e");
      return -1;
    }

    return 0;
  }

  Future<int> upgrade() async {
    if (executor.persistentStore == null) {
      displayError(_noDBConfigString);
      return -1;
    }

    Map<int, File> versionMap = executor.migrationFiles.fold({}, (map, file) {
      var versionNumber = executor.versionNumberFromFile(file);
      map[versionNumber] = file;
      return map;
    });

    var currentVersion = await executor.persistentStore.schemaVersion;
    var versionsToApply =
        versionMap.keys.where((v) => v > currentVersion).toList();
    if (versionsToApply.length == 0) {
      displayInfo("Database version is current (version: $currentVersion).");
      return 0;
    }

    displayInfo("Applying migration versions: ${versionsToApply.join(", ")}");
    try {
      await executor.upgrade();
    } catch (e) {
      displayError(
          "Upgrade failed. Version is now at ${await executor.persistentStore.schemaVersion}.\n$e");
      return -1;
    }

    displayError(
        "Upgrade successful. Version is now at ${await executor.persistentStore.schemaVersion}.");

    return 0;
  }

  Future<int> generate() async {
    try {
      var file = await executor.generate();

      displayInfo("Created new migration file ${file.uri}.");
    } catch (e) {
      displayError("Could not generate migration file.\n$e");
      return -1;
    }
    return 0;
  }

  @override
  Future cleanup() async {
    await executor?.persistentStore?.close();
  }

  String get _noDBConfigString {
    return "No database configuration file found. This tool expects a file at migrations/migration.yaml in this project's directory. This file contains connection configuration information and has the following format: $_dbConfigFormat";
  }
}
