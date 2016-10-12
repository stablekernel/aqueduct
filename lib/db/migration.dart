part of aqueduct;

class MigrationException {
  MigrationException(this.message);
  String message;
}

abstract class Migration {
  Schema get currentSchema => database.schema;
  PersistentStore get store => database.store;
  SchemaBuilder database;

  Future upgrade();

  Future downgrade();

  Future seed();
}

class MigrationExecutor {
  MigrationExecutor(this.persistentStore, this.projectDirectoryPath, this.libraryName, this.migrationFileDirectory);

  PersistentStore persistentStore;
  Uri migrationFileDirectory;
  Uri projectDirectoryPath;
  String libraryName;

  List<File> get migrationFiles  {
    var dir = new Directory.fromUri(migrationFileDirectory);
    var files = dir.listSync()
        .where((fse) => fse is File)
        .map((fse) => fse as File)
        .where((fse) => fse.path.endsWith(".migration.dart"))
        .toList();

    files.forEach((fse) {
      var fileName = fse.uri.pathSegments.last;
      var migrationName = fileName.split(".").first;
      var versionNumber = migrationName.split("_").first;
      try {
        int.parse(versionNumber);
      } catch (e) {
        throw new MigrationException("Migration files must have the following format: Version_Name.migration.dart, where Version must be an integer (no longer than 8 characters, optionally prefixed with 0s, e.g. '00000002') and '_Name' is optional. Offender: ${fse.uri}");
      }
    });

    files.sort((fs1, fs2) => fs1.uri.pathSegments.last.padLeft(8, "0").compareTo(fs2.uri.pathSegments.last.padLeft(8, "0")));

    return files;
  }

  Future validate() async {

  }

  Future<String> generate() async {
    var files = migrationFiles;
    if (!files.isEmpty) {
      // For now, just make a new empty one...
    }

    // Create the initial migration file
    // 1. Get the Schema from the package
    // 2. Run schemabuilder.sourceForSchemaUpgrade

    ///Users/joeconway/Projects/aqueduct/example/templates/default/lib/wildfire.dart

    print("${libraryName}");
    // ALWAYS run this from the project directory.
    var generator = new _SourceGenerator((List<String> args, Map<String, dynamic> values) async {
      var dataModel = new DataModel.fromURI(new Uri(scheme: "package", path: args[0]));
      var schema = new Schema.fromDataModel(dataModel);

      return SchemaBuilder.sourceForSchemaUpgrade(new Schema.empty(), schema, 1);
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName",
      "dart:isolate",
      "dart:mirrors",
      "dart:async",
      "dart:convert"
    ]);

    var executor = new _IsolateExecutor(generator, [libraryName], packageConfigURI: projectDirectoryPath.resolve(".packages"));

    return await executor.execute(workingDirectory: projectDirectoryPath);
  }

  Future<Schema> upgrade() async {
    var files = migrationFiles;
    if (files.isEmpty) {
      return null;
    }

    await persistentStore.createVersionTableIfNecessary();
    var currentVersion = await persistentStore.schemaVersion;

    var latestMigrationFile = files.last;
    var latestMigrationVersionNumber = _versionNumberFromFile(latestMigrationFile);

    List<File> migrationFilesToRun = [];
    List<File> migrationFilesToGetToCurrent = [];
    if (currentVersion == 0) {
      migrationFilesToRun = files;
    } else if (latestMigrationVersionNumber > currentVersion) {
      var indexOfCurrent = files.indexOf(files.firstWhere((f) => _versionNumberFromFile(f) == latestMigrationVersionNumber));
      migrationFilesToGetToCurrent = files.sublist(0, indexOfCurrent + 1);
      migrationFilesToRun = files.sublist(indexOfCurrent + 1);
    } else {
      migrationFilesToGetToCurrent = files;
    }

    var schema = new Schema.empty();
    for (var migration in migrationFilesToGetToCurrent) {
      schema = await _executeUpgradeForFile(migration, schema, dryRun: true);
    }

    for (var migration in migrationFilesToRun) {
      schema = await _executeUpgradeForFile(migration, schema, dryRun: false);
    }

    return schema;
  }

  int _versionNumberFromFile(File file) {
    var fileName = file.uri.pathSegments.last;
    var migrationName = fileName.split(".").first;
    return int.parse(migrationName.split("_").first);
  }

  Future<Schema> _executeUpgradeForFile(File file, Schema schema, {bool dryRun: false}) async {
    var versionNumber = _versionNumberFromFile(file);
    Map<String, dynamic> dbInfo;
    if (persistentStore is PostgreSQLPersistentStore) {
      var s = persistentStore as PostgreSQLPersistentStore;
      dbInfo = {
        "flavor" : "postgres",
        "username" : s.username,
        "password" : s.password,
        "host" : s.host,
        "port" : s.port,
        "databaseName" : s.databaseName,
        "timeZone" : s.timeZone
      };
    }

    var message = {
      "dryRun" : dryRun,
      "schema" : schema.asMap(),
      "dbInfo" : dbInfo,
    };

    var generator = new _SourceGenerator((List<String> args, Map<String, dynamic> values) async {
      var inputSchema = new Schema.fromMap(values["schema"] as Map<String, dynamic>);
      var dbInfo = values["dbInfo"];
      var dryRun = values["dryRun"];

      PersistentStore store;
      if (dbInfo["flavor"] == "postgres") {
        store = new PostgreSQLPersistentStore.fromConnectionInfo(dbInfo["username"], dbInfo["password"], dbInfo["host"], dbInfo["port"], dbInfo["databaseName"], timeZone: dbInfo["timeZone"]);
      }

      var versionNumber = int.parse(args.first);
      var migrationClassMirror = currentMirrorSystem().isolate.rootLibrary.declarations.values.firstWhere((dm) => dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration))) as ClassMirror;
      var migrationInstance = migrationClassMirror.newInstance(new Symbol(''), []).reflectee as Migration;
      migrationInstance.database = new SchemaBuilder(store, inputSchema);

      await migrationInstance.upgrade();
      if (!dryRun) {
        await migrationInstance.database.execute(versionNumber);
        await migrationInstance.database.store.close();
      }

      return migrationInstance.currentSchema.asMap();
    }, imports: ["dart:isolate", "dart:mirrors"], additionalContents: file.readAsStringSync());

    var executor = new _IsolateExecutor(generator, ["$versionNumber"], message: message);
    var schemaMap = await executor.execute();
    return new Schema.fromMap(schemaMap as Map<String, dynamic>);
  }
}