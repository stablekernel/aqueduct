part of aqueduct;

class MigrationConfiguration extends ConfigurationItem {
  MigrationConfiguration(String filename) : super.fromFile(filename);

  DatabaseConnectionConfiguration migration;
}

class MigrationRunner extends CLICommand {
  MigrationExecutor executor;
  ArgParser options = new ArgParser(allowTrailingOptions: false)
    ..addOption("flavor", abbr: "f", help: "The database driver flavor to use.", defaultsTo: "postgres", allowed: ["postgres"])
    ..addOption("dbconfig", abbr: "c", help: "A configuration file that provides values for database connection that will execute the migration. This must be a filename and the file must be in migration-directory.", defaultsTo: "migration.yaml")
    ..addOption("migration-directory", abbr: "d", help: "The directory where migration files are stored. This path may be relative to the project directory (which must also be the current working directory)", defaultsTo: "migrations")
    ..addCommand("validate")
    ..addCommand("upgrade")
    ..addCommand("generate")
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

    executor = new MigrationExecutor(store, directoryURI);

    if (argValues.command?.name == "validate") {
      return await validate();
    } else if (argValues.command?.name == "list-versions") {
      return await listVersions();
    } else if (argValues.command?.name == "version") {
      return await printVersion();
    } else if (argValues.command?.name == "upgrade") {
      return await upgrade();
    } else if (argValues.command?.name == "generate") {
      return await generate();
    }

    print("Invalid command, options for db are: ${options.commands.keys.join(", ")}");
    return -1;
  }

  Future<int> validate() async {
    return 0;
  }

  Future<int> listVersions() async {
    var files = executor.migrationFiles.map((f) {
      var versionString = "${executor._versionNumberFromFile(f)}".padLeft(8, "0");
      return " $versionString | ${f.path}";
    }).join("\n");

    print(" Version  | Path");
    print("----------|-----------");
    print("$files");

    return 0;
  }

  Future<int> printVersion() async {
    try {
      var current = await executor.persistentStore.schemaVersion;
      print("Current version: $current");
    } catch (e) {
      print("Could not determine schema version. Does database exist (with a version table) and can it be connected to?");
      return -1;
    }

    return 0;
  }

  Future<int> upgrade() async {
    Map<int, File> versionMap = executor.migrationFiles.fold({}, (map, file) {
      var versionNumber = executor._versionNumberFromFile(file);
      map[versionNumber] = file;
      return map;
    });

    var currentVersion = await executor.persistentStore.schemaVersion;
    var versionsToApply = versionMap.keys.where((v) => v > currentVersion).toList();
    if (versionsToApply == 0) {
      print("Database version is current (version: $currentVersion).");
      return 0;
    }



    return 0;
  }

  Future<int> generate() async {
    return 0;
  }
}