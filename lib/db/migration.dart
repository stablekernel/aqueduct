part of aqueduct;

abstract class Migration {
  Schema get currentSchema => database.inputSchema;
  PersistentStore get store => database.store;
  SchemaBuilder database;

  // This needs to be wrapped in a transaction.
  Future upgrade();

  // This needs to be wrapped in a transaction.
  Future downgrade();

  Future seed();
}

class MigrationExecutor {
  MigrationExecutor(this.persistentStore, this.migrationFileDirectory);

  PersistentStore persistentStore;
  Uri migrationFileDirectory;

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
        throw new MigrationException("Migration files must have the following format: Version_Name.migration.dart, where Version must be an integer (no longer than 8 characters) and '_Name' is optional. Offender: ${fse.uri}");
      }
    });

    files.sort((fs1, fs2) => fs1.uri.pathSegments.last.padLeft(8, "0").compareTo(fs2.uri.pathSegments.last.padLeft(8, "0")));

    return files;
  }

  Future<bool> upgrade() async {
    await persistentStore.createVersionTableIfNecessary();

    var files = migrationFiles;
    if (files.isEmpty) {
      return false;
    }

    var latestMigrationFile = files.last;
    var latestMigrationVersionNumber = _versionNumberFromFile(latestMigrationFile);
    var currentVersion = await persistentStore.schemaVersion;

    List<File> migrationFilesToRun;
    List<File> migrationFilesToGetToCurrent = [];
    if (currentVersion == 0) {
      migrationFilesToRun = files;
    } else if (latestMigrationVersionNumber > currentVersion) {
      var indexOfCurrent = files.indexOf(files.firstWhere((f) => _versionNumberFromFile(f) == latestMigrationVersionNumber));
      migrationFilesToGetToCurrent = files.sublist(0, indexOfCurrent + 1);
      migrationFilesToRun = files.sublist(indexOfCurrent + 1);
    }

    if (migrationFilesToRun == null) {
      return false;
    }

    var schema = new Schema.empty();
    for (var migration in migrationFilesToGetToCurrent) {
      schema = await _executeUpgradeForFile(migration, schema, dryRun: true);
    }

    for (var migration in migrationFilesToRun) {
      schema = await _executeUpgradeForFile(migration, schema, dryRun: false);
    }

    return true;
  }

  int _versionNumberFromFile(File file) {
    var fileName = file.uri.pathSegments.last;
    var migrationName = fileName.split(".").first;
    return int.parse(migrationName.split("_").first);
  }

  Future<Schema> _executeUpgradeForFile(File file, Schema schema, {bool dryRun: false}) async {
    var versionNumber = _versionNumberFromFile(file);
    var onFinish = new Completer();
    var source = _upgradeContentsForMigrationContents(file.readAsStringSync());
    var tmpFile = new File("${file.path}.tmp");
    try {
      tmpFile.writeAsStringSync(source);

      var onErrorPort = new ReceivePort()
        ..listen((err) {
          if (!onFinish.isCompleted) {
            onFinish.completeError(err);
          }
        });

      var controlPort = new ReceivePort()
        ..listen((results) {
          onFinish.complete(results);
        });

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

      await Isolate.spawnUri(tmpFile.uri, ["$versionNumber"], {
        "dryRun" : dryRun,
        "schema" : schema.asMap(),
        "sendPort" : controlPort.sendPort,
        "dbInfo" : dbInfo,
      }, errorsAreFatal: true, onError: onErrorPort.sendPort);

      return onFinish.future;
    } finally {
      tmpFile.deleteSync();
    }
  }

  String _upgradeContentsForMigrationContents(String contents) {
    var f = (List<String> args, Map<String, dynamic> values) async {
      SendPort sendPort = values["sendPort"];
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

      var outSchema = migrationInstance.currentSchema;
      sendPort.send(outSchema.asMap());
    };

    var source = (reflect(f) as ClosureMirror).function.source;
    var builder = new StringBuffer();
    builder.writeln("import 'dart:isolate';");
    builder.writeln("import 'dart:mirrors';");
    builder.writeln(contents);
    builder.writeln("");
    builder.writeln("Future main (List<String> args, Map<String, dynamic> sendPort) async {");
    builder.writeln("  var f = $source;");
    builder.writeln("  await f(args, sendPort);");
    builder.writeln("}");

    return builder.toString();
  }
}

class MigrationException {
  MigrationException(this.message);
  String message;
}