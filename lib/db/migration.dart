part of aqueduct;

class MigrationException {
  MigrationException(this.message);
  String message;

  String toString() => message;
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

    Map<int, File> orderMap = dir.listSync()
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
            throw new MigrationException("Migration files must have the following format: Version_Name.migration.dart, where Version must be an integer (optionally prefixed with 0s, e.g. '00000002') and '_Name' is optional. Offender: ${fse.uri}");
          }
        });

    var sortedKeys = (new List.from(orderMap.keys));
    sortedKeys.sort((int a, int b) => a.compareTo(b));
    return sortedKeys.map((v) => orderMap[v]).toList();
  }

  Future<Schema> validate() async {
    var directory = new Directory.fromUri(migrationFileDirectory);
    if (!directory.existsSync()) {
      throw new MigrationException("Migration directory doesn't exist, nothing to validate.");
    }

    var files = migrationFiles;
    if (files.isEmpty) {
      throw new MigrationException("Migration directory doesn't contain any migrations, nothing to validate.");
    }

    var generator = new _SourceGenerator((List<String> args, Map<String, dynamic> values) async {
      var dataModel = new DataModel.fromURI(new Uri(scheme: "package", path: args[0]));
      var schema = new Schema.fromDataModel(dataModel);

      return schema.asMap();
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName",
      "dart:isolate",
      "dart:mirrors",
      "dart:async"
    ]);

    var executor = new _IsolateExecutor(generator, [libraryName], packageConfigURI: projectDirectoryPath.resolve(".packages"));
    var projectSchema = new Schema.fromMap(await executor.execute(workingDirectory: projectDirectoryPath) as Map<String, dynamic>);

    var schema = new Schema.empty();
    for (var migration in migrationFiles) {
      schema = await _executeUpgradeForFile(migration, schema, dryRun: true);
    }

    var errors = <String>[];
    var matches = schema.matches(projectSchema, errors);

    if (!matches) {
      throw new MigrationException("Validation failed:\n\t${errors.join("\n\t")}");
    }

    return schema;
  }

  Future<File> generate() async {
    _createMigrationDirectoryIfNecessary();
    _ensurePackageResolutionAvailable();

    var files = migrationFiles;
    if (!files.isEmpty) {
      // For now, just make a new empty one...
      var newVersionNumber = _versionNumberFromFile(files.last) + 1;
      var contents = SchemaBuilder.sourceForSchemaUpgrade(new Schema.empty(), new Schema.empty(), newVersionNumber);
      var file = new File.fromUri(migrationFileDirectory.resolve("${"$newVersionNumber".padLeft(8, "0")}_Unnamed.migration.dart"));
      file.writeAsStringSync(contents);

      return file;
    }

    var generator = new _SourceGenerator((List<String> args, Map<String, dynamic> values) async {
      var dataModel = new DataModel.fromURI(new Uri(scheme: "package", path: args[0]));
      var schema = new Schema.fromDataModel(dataModel);

      return SchemaBuilder.sourceForSchemaUpgrade(new Schema.empty(), schema, 1);
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName",
      "dart:isolate",
      "dart:mirrors",
      "dart:async"
    ]);

    var executor = new _IsolateExecutor(generator, [libraryName], packageConfigURI: projectDirectoryPath.resolve(".packages"));
    var contents = await executor.execute(workingDirectory: projectDirectoryPath);
    var file = new File.fromUri(migrationFileDirectory.resolve("00000001_Initial.migration.dart"));
    file.writeAsStringSync(contents);

    return file;
  }

  Future<Schema> upgrade() async {
    var directory = new Directory.fromUri(migrationFileDirectory);
    if (!directory.existsSync()) {
      throw new MigrationException("Migration directory doesn't exist, nothing to upgrade.");
    }

    var files = migrationFiles;
    if (files.isEmpty) {
      throw new MigrationException("Migration directory doesn't contain any migrations, nothing to upgrade.");
    }

    var currentVersion = await persistentStore.schemaVersion;
    var migrationFileSplit = _splitMigrationFiles(currentVersion);
    var migrationFilesToGetToCurrent = migrationFileSplit.first;
    List<File> migrationFilesToRun = migrationFileSplit.last;

    var schema = new Schema.empty();
    for (var migration in migrationFilesToGetToCurrent) {
      schema = await _executeUpgradeForFile(migration, schema, dryRun: true);
    }

    for (var migration in migrationFilesToRun) {
      schema = await _executeUpgradeForFile(migration, schema, dryRun: false);
    }

    return schema;
  }

  ///////

  int _versionNumberFromFile(File file) {
    var fileName = file.uri.pathSegments.last;
    var migrationName = fileName.split(".").first;
    return int.parse(migrationName.split("_").first);
  }

  List<List<File>> _splitMigrationFiles(int aroundVersion) {
    var files = migrationFiles;
    var latestMigrationFile = files.last;
    var latestMigrationVersionNumber = _versionNumberFromFile(latestMigrationFile);

    List<File> migrationFilesToRun = [];
    List<File> migrationFilesToGetToCurrent = [];
    if (aroundVersion == 0) {
      migrationFilesToRun = files;
    } else if (latestMigrationVersionNumber > aroundVersion) {
      var indexOfCurrent = files.indexOf(files.firstWhere((f) => _versionNumberFromFile(f) == aroundVersion));
      migrationFilesToGetToCurrent = files.sublist(0, indexOfCurrent + 1);
      migrationFilesToRun = files.sublist(indexOfCurrent + 1);
    } else {
      migrationFilesToGetToCurrent = files;
    }

    return [migrationFilesToGetToCurrent, migrationFilesToRun];
  }

  Future<Schema> _executeUpgradeForFile(File file, Schema schema, {bool dryRun: false}) async {
    var generator = new _SourceGenerator((List<String> args, Map<String, dynamic> values) async {
      var inputSchema = new Schema.fromMap(values["schema"] as Map<String, dynamic>);
      var dbInfo = values["dbInfo"];
      var dryRun = values["dryRun"];

      PersistentStore store;
      if (dbInfo != null && dbInfo["flavor"] == "postgres") {
        store = new PostgreSQLPersistentStore.fromConnectionInfo(dbInfo["username"], dbInfo["password"], dbInfo["host"], dbInfo["port"], dbInfo["databaseName"], timeZone: dbInfo["timeZone"]);
      }

      var versionNumber = int.parse(args.first);
      var migrationClassMirror = currentMirrorSystem().isolate.rootLibrary.declarations.values
          .firstWhere((dm) => dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration))) as ClassMirror;
      var migrationInstance = migrationClassMirror.newInstance(new Symbol(''), []).reflectee as Migration;
      migrationInstance.database = new SchemaBuilder(store, inputSchema);

      await migrationInstance.upgrade();

      if (!dryRun && !migrationInstance.database.commands.isEmpty) {
        await migrationInstance.store.upgrade(versionNumber, migrationInstance.database.commands);
        await migrationInstance.seed();
        await migrationInstance.database.store.close();

      }

      return migrationInstance.currentSchema.asMap();
    }, imports: ["dart:async", "package:aqueduct/aqueduct.dart", "dart:isolate", "dart:mirrors"], additionalContents: file.readAsStringSync());

    var executor = new _IsolateExecutor(generator, ["${_versionNumberFromFile(file)}"], message: {
      "dryRun" : dryRun,
      "schema" : schema.asMap(),
      "dbInfo" : _storeConnectionMap,
    });
    var schemaMap = await executor.execute();
    return new Schema.fromMap(schemaMap as Map<String, dynamic>);
  }

  Map<String, dynamic> get _storeConnectionMap {
    if (persistentStore is PostgreSQLPersistentStore) {
      var s = persistentStore as PostgreSQLPersistentStore;
      return {
        "flavor" : "postgres",
        "username" : s.username,
        "password" : s.password,
        "host" : s.host,
        "port" : s.port,
        "databaseName" : s.databaseName,
        "timeZone" : s.timeZone
      };
    }

    return null;
  }

  void _createMigrationDirectoryIfNecessary() {
    var directory = new Directory.fromUri(migrationFileDirectory);
    if (!directory.existsSync()) {
      directory.createSync();
    }
  }

  void _ensurePackageResolutionAvailable() {
    var file = new File.fromUri(projectDirectoryPath.resolve(".packages"));
    if (!file.existsSync()) {
      throw new MigrationException("No .packages file. Run pub get.");
    }
  }
}