import 'dart:mirrors';
import 'dart:async';
import 'dart:io';

import 'package:safe_config/safe_config.dart';
import 'package:yaml/yaml.dart';

import '../utilities/source_generator.dart';
import '../db/db.dart';
import 'base.dart';
import 'db_generate.dart';
import 'db_show_migrations.dart';
import 'db_upgrade.dart';
import 'db_validate.dart';
import 'db_version.dart';

class CLIDatabase extends CLICommand {
  CLIDatabase() {
    options
      ..addOption("migration-directory",
          abbr: "m",
          help:
              "The directory where migration files are stored. Relative paths are relative to the application-directory.",
          defaultsTo: "migrations");

    registerCommand(new CLIDatabaseUpgrade());
    registerCommand(new CLIDatabaseGenerate());
    registerCommand(new CLIDatabaseShowMigrations());
    registerCommand(new CLIDatabaseValidate());
    registerCommand(new CLIDatabaseVersion());
  }

  String get name {
    return "db";
  }

  String get description {
    return "Modifies, verifies and generates database schemas.";
  }

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

  Future<int> handle() async {
    printHelp();
    return 0;
  }
}

abstract class CLIDatabaseConnectingCommand extends CLICommand
    with CLIDatabaseMigratable, CLIProject {
  static const String FlavorPostgreSQL = "postgres";

  CLIDatabaseConnectingCommand() {
    options
      ..addOption("flavor",
          abbr: "f",
          help: "The database driver flavor to use.",
          defaultsTo: "postgres",
          allowed: ["postgres"])
      ..addOption("connect",
          abbr: "c",
          help:
              "A database connection URI string. If this option is set, database-config is ignored.",
          valueHelp: "postgres://user:password@localhost:port/databaseName")
      ..addOption("database-config",
          help:
              "A configuration file that provides connection information for the database. "
              "Paths are relative to project directory. If the connect option is set, this value is ignored. "
              "See 'aqueduct db -h' for details.",
          defaultsTo: "database.yaml")
      ..addFlag("use-ssl",
          help: "Whether or not the database connection should use SSL",
          defaultsTo: false);
  }

  DatabaseConnectionConfiguration connectedDatabase;
  bool get useSSL => values["use-ssl"];
  String get databaseConnectionString => values["connect"];
  String get databaseFlavor => values["flavor"];
  File get databaseConfigurationFile =>
      fileInProjectDirectory(values["database-config"]);

  PersistentStore _persistentStore;
  PersistentStore get persistentStore {
    if (_persistentStore != null) {
      return _persistentStore;
    }

    if (values["flavor"] == null) {
      throw new CLIException("No database flavor selected. See --flavor.");
    }

    if (databaseFlavor == FlavorPostgreSQL) {
      connectedDatabase = new DatabaseConnectionConfiguration();
      if (databaseConnectionString != null) {
        try {
          connectedDatabase.decode(databaseConnectionString);
        } catch (_) {
          throw new CLIException("Invalid database configuration.",
              instructions: [
                "Invalid connection string was: $databaseConnectionString",
                "Expected format:               database://user:password@host:port/databaseName"
              ]);
        }
      } else {
        if (!databaseConfigurationFile.existsSync()) {
          throw new CLIException("No database configuration file found.",
              instructions: [
                "Expected file at: ${databaseConfigurationFile.path}.",
                "See --connect and --database-config. If not using --connect, "
                    "this tool expects a YAML configuration file with the following format:\n$_dbConfigFormat"
              ]);
        }

        try {
          var contents = databaseConfigurationFile.readAsStringSync();
          var yaml = loadYaml(contents);
          connectedDatabase.readFromMap(yaml);
        } catch (_) {
          throw new CLIException("Invalid database configuration.",
              instructions: [
                "File located at ${databaseConfigurationFile.path}.",
                "See --connect and --database-config. If not using --connect, "
                    "this tool expects a YAML configuration file with the following format:\n$_dbConfigFormat"
              ]);
        }
      }

      _persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo(
          connectedDatabase.username,
          connectedDatabase.password,
          connectedDatabase.host,
          connectedDatabase.port,
          connectedDatabase.databaseName,
          useSSL: useSSL);
      return _persistentStore;
    }

    throw new CLIException("Invalid flavor ${databaseFlavor}");
  }

  @override
  Future cleanup() async {
    return _persistentStore?.close();
  }

  String get _dbConfigFormat {
    return "\n\tusername: username\n\tpassword: password\n\thost: host\n\tport: port\n\tdatabaseName: name\n";
  }
}

abstract class CLIDatabaseMigratable{
  Directory get projectDirectory;

  Directory get migrationDirectory {
    var dir = new Directory.fromUri(projectDirectory.uri.resolve("migrations"));
    if (!dir.existsSync()) {
      dir.createSync();
    }
    return dir;
  }

  List<File> get migrationFiles {
    Map<int, File> orderMap = migrationDirectory
        .listSync()
        .where((fse) => fse is File && fse.path.endsWith(".migration.dart"))
        .fold({}, (m, fse) {
      var fileName = fse.uri.pathSegments.last;
      var migrationName = fileName.split(".").first;
      var versionNumberString = migrationName.split("_").first;

      try {
        var versionNumber = int.parse(versionNumberString);
        m[versionNumber] = fse;
        return m;
      } catch (e) {
        throw new CLIException(
            "Migration files must have the following format: Version_Name.migration.dart,"
            "where Version must be an integer (optionally prefixed with 0s, e.g. '00000002')"
            " and '_Name' is optional. Offender: ${fse.uri}");
      }
    });

    var sortedKeys = (new List.from(orderMap.keys));
    sortedKeys.sort((int a, int b) => a.compareTo(b));
    return sortedKeys.map((v) => orderMap[v]).toList();
  }

  int versionNumberFromFile(File file) {
    var fileName = file.uri.pathSegments.last;
    var migrationName = fileName.split(".").first;
    return int.parse(migrationName.split("_").first);
  }

  Future<Schema> schemaByApplyingMigrationFile(File migrationFile, Schema fromSchema) async {
    var sourceFunction =
        (List<String> args, Map<String, dynamic> values) async {
      var inputSchema =
        new Schema.fromMap(values["schema"] as Map<String, dynamic>);

      var versionNumber = int.parse(args.first);
      var migrationClassMirror = currentMirrorSystem()
          .isolate
          .rootLibrary
          .declarations
          .values
          .firstWhere((dm) =>
      dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration)))
      as ClassMirror;

      var migrationInstance = migrationClassMirror
          .newInstance(new Symbol(''), []).reflectee as Migration;
      migrationInstance.database = new SchemaBuilder(null, inputSchema);

      await migrationInstance.upgrade();

      return migrationInstance.currentSchema.asMap();
    };

    var generator = new SourceGenerator(sourceFunction,
        imports: [
          "dart:async",
          "package:aqueduct/aqueduct.dart",
          "dart:isolate",
          "dart:mirrors"
        ],
        additionalContents: migrationFile.readAsStringSync());

    var schemaMap = await IsolateExecutor.executeSource(generator,
        ["${versionNumberFromFile(migrationFile)}"], projectDirectory.uri,
        message: {"schema": fromSchema.asMap()});

    return new Schema.fromMap(schemaMap as Map<String, dynamic>);
  }
}

