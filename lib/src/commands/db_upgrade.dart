import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:logging/logging.dart';

import '../utilities/source_generator.dart';
import 'base.dart';
import 'db.dart';
import '../db/db.dart';

/// Used internally.
class CLIDatabaseUpgrade extends CLIDatabaseConnectingCommand {
  @override
  Future<int> handle() async {
    Map<int, File> versionMap = migrationFiles.fold({}, (map, file) {
      var versionNumber = versionNumberFromFile(file);
      map[versionNumber] = file;
      return map;
    });

    if (versionMap.isEmpty) {
      displayInfo("No migration files.");
      displayProgress("Run 'aqueduct db generate' first.");
      return 0;
    }

    var currentVersion = await persistentStore.schemaVersion;
    var versionsToApply = versionMap.keys.where((v) => v > currentVersion).toList();
    if (versionsToApply.length == 0) {
      displayInfo("Database version is already current (version: $currentVersion).");
      return 0;
    }

    displayInfo("Updating to version: ${versionsToApply.last}...");
    displayProgress("From version: $currentVersion");
    var migrationFileSplit = splitMigrationFiles(currentVersion);
    var migrationFilesToGetToCurrent = migrationFileSplit.first;
    List<File> migrationFilesToRun = migrationFileSplit.last;

    var pattern = new RegExp(r"<<\s*set\s*>>");
    for (var file in migrationFilesToRun) {
      var contents = file.readAsStringSync();
      if (contents.contains(pattern)) {
        displayError("Migration file needs input");
        displayProgress("Migration file: ${file.path}");
        displayProgress(
            "An ambiguous change to the schema requires your input in the referenced file. Search for '<<set>>' and replace with an appropriate value.");
        return 1;
      }
    }

    var schema = new Schema.empty();
    for (var migration in migrationFilesToGetToCurrent) {
      displayProgress("Replaying version ${versionNumberFromFile(migration)}");
      schema = await schemaByApplyingMigrationFile(migration, schema);
    }

    for (var migration in migrationFilesToRun) {
      displayInfo("Applying version ${versionNumberFromFile(migration)}...");
      schema = await executeUpgradeForFile(migration, schema, _storeConnectionMap);
      displayProgress("Applied version ${versionNumberFromFile(migration)} successfully.", color: CLIColor.green);
    }

    return 0;
  }

  @override
  String get name {
    return "upgrade";
  }

  @override
  String get description {
    return "Executes migration files against a database.";
  }

  List<List<File>> splitMigrationFiles(int aroundVersion) {
    var files = migrationFiles;
    var latestMigrationFile = files.last;
    var latestMigrationVersionNumber = versionNumberFromFile(latestMigrationFile);

    List<File> migrationFilesToRun = [];
    List<File> migrationFilesToGetToCurrent = [];
    if (aroundVersion == 0) {
      migrationFilesToRun = files;
    } else if (latestMigrationVersionNumber > aroundVersion) {
      var indexOfCurrent = files.indexOf(files.firstWhere((f) => versionNumberFromFile(f) == aroundVersion));
      migrationFilesToGetToCurrent = files.sublist(0, indexOfCurrent + 1);
      migrationFilesToRun = files.sublist(indexOfCurrent + 1);
    } else {
      migrationFilesToGetToCurrent = files;
    }

    return [migrationFilesToGetToCurrent, migrationFilesToRun];
  }

  Future<Schema> executeUpgradeForFile(File file, Schema schema, Map<String, dynamic> connectionInfo) async {
    var generator = new SourceGenerator((List<String> args, Map<String, dynamic> values) async {
      hierarchicalLoggingEnabled = true;

      PostgreSQLPersistentStore.logger.level = Level.ALL;
      PostgreSQLPersistentStore.logger.onRecord.listen((r) => print("\t${r.message}"));

      var inputSchema = new Schema.fromMap(values["schema"] as Map<String, dynamic>);
      var dbInfo = values["dbInfo"];

      PersistentStore store;
      if (dbInfo != null && dbInfo["flavor"] == "postgres") {
        store = new PostgreSQLPersistentStore(
            dbInfo["username"], dbInfo["password"], dbInfo["host"], dbInfo["port"], dbInfo["databaseName"],
            timeZone: dbInfo["timeZone"]);
      }

      var versionNumber = int.parse(args.first);
      var migrationClassMirror = currentMirrorSystem()
          .isolate
          .rootLibrary
          .declarations
          .values
          .firstWhere((dm) => dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration))) as ClassMirror;

      var migrationInstance = migrationClassMirror.newInstance(new Symbol(''), []).reflectee as Migration;
      migrationInstance.database = new SchemaBuilder(store, inputSchema);
      await migrationInstance.store.upgrade(versionNumber, migrationInstance);
      await migrationInstance.database.store.close();

      return migrationInstance.currentSchema.asMap();
    }, imports: [
      "dart:async",
      "package:aqueduct/aqueduct.dart",
      "package:logging/logging.dart",
      "dart:isolate",
      "dart:mirrors"
    ], additionalContents: file.readAsStringSync());

    var executor = new IsolateExecutor(generator, ["${versionNumberFromFile(file)}"],
        message: {"schema": schema.asMap(), "dbInfo": connectionInfo},
        packageConfigURI: projectDirectory.uri.resolve(".packages"));

    var schemaMap = await executor.execute();
    return new Schema.fromMap(schemaMap as Map<String, dynamic>);
  }

  Map<String, dynamic> get _storeConnectionMap {
    var s = persistentStore;
    if (s is PostgreSQLPersistentStore) {
      return {
        "flavor": "postgres",
        "username": s.username,
        "password": s.password,
        "host": s.host,
        "port": s.port,
        "databaseName": s.databaseName,
        "timeZone": s.timeZone
      };
    }

    return null;
  }
}
