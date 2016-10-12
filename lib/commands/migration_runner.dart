part of aqueduct;

class MigrationConfiguration extends ConfigurationItem {
  MigrationConfiguration(String filename) : super.fromFile(filename);

  DatabaseConnectionConfiguration migration;
}

class MigrationRunner extends CLICommand {
  MigrationExecutor executor;
  ArgParser options = new ArgParser(allowTrailingOptions: false)
    ..addOption("flavor", abbr: "f", help: "The database driver flavor to use.", defaultsTo: "postgres", allowed: ["postgres"])
    ..addOption("dbconfig", abbr: "d", help: "A configuration file that provides connection information for the database that the migration will be executed on. Relative paths are relative to the migration-directory.", defaultsTo: "migration.yaml")
    ..addOption("migration-directory", abbr: "m", help: "The directory where migration files are stored. Relative paths are relative to the application-directory.", defaultsTo: "migrations")
    ..addOption("application-directory", abbr: "a", help: "An Aqueduct application project directory. This directory must contain a pubspec.yaml file. Relative paths are relative to the current working directory.", defaultsTo: Directory.current.path)
    ..addOption("library-name", abbr: "l", help: "The name of the application library file in the package, without the .dart suffix. This name is resolved according to the .packages mapping in the application-directory. By default, this value will be the name of the application package defined in pubspec.yaml. Thus, a package with the name 'foobar' will default to 'foobar', and the library file is then 'package:foobar/foobar.dart'.")
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

    var projectURI = new Uri.directory(argValues["application-directory"]);
    if (!projectURI.isAbsolute) {
      projectURI = Directory.current.uri.resolveUri(projectURI);
    }

    var packageName = _getPackageName(projectURI);
    var libraryPath = "$packageName/${argValues["library-name"] ?? packageName}.dart";

    Uri migrationDirectoryURI = new Uri.directory(argValues["migration-directory"]);
    if (!migrationDirectoryURI.isAbsolute) {
      migrationDirectoryURI = projectURI.resolveUri(migrationDirectoryURI);

      var directory = new Directory.fromUri(migrationDirectoryURI);
      if (!directory.existsSync()) {
        directory.createSync();
      }
    }

    Uri dbConfigURI = new Uri.file(argValues["dbconfig"]);
    if (!dbConfigURI.isAbsolute) {
      dbConfigURI = migrationDirectoryURI.resolveUri(dbConfigURI);
    }

    PersistentStore store = null;
    if (argValues["flavor"] == "postgres") {
      if (new File.fromUri(dbConfigURI).existsSync()) {
        var dbConfig = new MigrationConfiguration(dbConfigURI.path).migration;
        store = new PostgreSQLPersistentStore.fromConnectionInfo(dbConfig.username, dbConfig.password, dbConfig.host, dbConfig.port, dbConfig.databaseName);
      }
    } else {
      print("Invalid flavor ${argValues["flavor"]}\n\n${options.usage}");
      return -1;
    }

    executor = new MigrationExecutor(store, projectURI, libraryPath, migrationDirectoryURI);

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
    try {
      await executor.validate();
      print("Success! The migration files in ${executor.migrationFileDirectory} will create a schema that matches the data model in ${executor.projectDirectoryPath}.");

      return 0;
    } catch (e) {
      print("Invalid migrations\n");
      print("$e");
      return -1;
    }
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
      print("Could not determine schema version. Does database exist (with a version table) and can it be connected to?\n$e");
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

    print("Applying migrations: ${versionsToApply.join(", ")}...");
    try {
      await executor.upgrade();
    } catch (e) {
      print("Upgrade failed. Version is now at ${await executor.persistentStore.schemaVersion}.\n$e");
      return -1;
    }

    print("Upgrade successful. Version is now at  ${await executor.persistentStore.schemaVersion}.");

    return 0;
  }

  Future<int> generate() async {
    try {
      var contents = await executor.generate();
      var migrationFiles = executor.migrationFiles;
      var versionString = "${"1".padLeft(8, "0")}_Initial.migration.dart";
      if (!migrationFiles.isEmpty) {
        var versionNumber = executor.migrationFiles.map((f) => executor._versionNumberFromFile(f)).last + 1;
        versionString = "$versionNumber".padLeft(8, "0") + "_Name.migration.dart";
      }

      var migrationFileURI = executor.migrationFileDirectory.resolve(versionString);
      new File.fromUri(migrationFileURI).writeAsStringSync(contents);

      print("Created new migration file $migrationFileURI.");
    } catch (e) {
      print("Could not generate migration file.\n$e");
      return -1;
    }
    return 0;
  }


  Future cleanup() async {
    await executor.persistentStore.close();
  }


  String _getPackageName(Uri projectURI) {
    var yamlContents = new File.fromUri(projectURI.resolve("pubspec.yaml")).readAsStringSync();
    var pubspec = loadYaml(yamlContents);

    return pubspec["name"];
  }
}