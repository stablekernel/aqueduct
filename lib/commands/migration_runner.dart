part of aqueduct;

class MigrationConfiguration extends ConfigurationItem {
  MigrationConfiguration(String filename) : super.fromFile(filename);

  DatabaseConnectionConfiguration migration;
}

class MigrationRunner extends CLICommand {
  ArgParser options = new ArgParser(allowTrailingOptions: false)
    ..addOption("flavor", abbr: "f", help: "The database driver flavor to use.", defaultsTo: "postgres", allowed: ["postgres"])
    ..addOption("dbconfig", abbr: "c", help: "A configuration file that provides values for database connection that will execute the migration. This must be a filename and the file must be in the migration-directory.", defaultsTo: "migration.yaml")
    ..addOption("migration-directory", abbr: "d", help: "The directory where migration files are stored.", defaultsTo: "migrations")
    ..addCommand("validate")
    ..addCommand("list-versions")
    ..addCommand("version")
    ..addFlag("help", negatable: false, help: "Shows this documentation");

  Future<int> handle(ArgResults argValues) async {
    if (argValues["help"] == true) {
      print("${options.usage}");
      return 0;
    }

    Uri directoryURI = null;
    String directoryArg = argValues["migration-directory"];
    if (directoryArg.startsWith("/")) {
      directoryURI = new Uri.file(directoryArg);
    } else {
      directoryURI = new Uri.file(Directory.current.path + "/$directoryArg");
    }

    var dbConfigPath = argValues["dbconfig"];
    var dbConfig = new MigrationConfiguration(directoryURI.path + "/$dbConfigPath").migration;
    PersistentStore store = null;
    if (argValues["flavor"] == "postgres") {
      store = new PostgreSQLPersistentStore.fromConnectionInfo(dbConfig.username, dbConfig.password, dbConfig.host, dbConfig.port, dbConfig.databaseName);
    } else {
      print("Invalid flavor ${argValues["flavor"]}\n\n${options.usage}");
      return -1;
    }

    var executor = new MigrationExecutor(store, directoryURI);
    await executor.persistentStore.createVersionTableIfNecessary();
    if (argValues.command?.name == "validate") {

    } else if (argValues.command?.name == "list-versions") {

      var files = executor.migrationFiles.map((f) {
        var versionString = "${executor._versionNumberFromFile(f)}".padLeft(8, "0");
        return " $versionString | ${f.path}";
      }).join("\n");

      print(" Version  | Path");
      print("----------|-----------");
      print("$files");

      return 0;
    } else if (argValues.command?.name == "version") {
      var current = await executor.persistentStore.schemaVersion;
      print("Current version: $current");
    } else if (argValues.command?.name == "upgrade") {
      return 0;
    }

    print("Invalid command, options for db are: ${options.commands.keys.join(", ")}");
    return -1;
  }
}