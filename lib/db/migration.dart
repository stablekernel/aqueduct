part of aqueduct;

abstract class Migration {
  Schema get currentSchema => database.currentSchema;
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
    var files = dir.listSync().where((fse) => fse.path.endsWith(".migration.dart")).toList();

    files.forEach((fse) {
      var fileName = fse.uri.pathSegments.last;
      var migrationName = fileName.split(".").first;
      var versionNumber = migrationName.split("_").first;
      try {
        int.parse(versionNumber);
      } catch (e) {
        throw new MigrationException("Migration files must have the following format: Version_Name.migration.dart, where Version must be an integer and '_Name' is optional. Offender: ${fse.uri}");
      }
    });

    files.sort((fs1, fs2) => fs1.uri.pathSegments.last.padLeft(8, "0").compareTo(fs2.uri.pathSegments.last.padLeft(8, "0")));

    return files;
  }

  Future<bool> upgrade() async {
    var files = migrationFiles;
    if (files.isEmpty) {
      throw new MigrationException("No migration files in ${migrationFileDirectory}.");
    }

    var latestMigrationFile = files.last;
    var latestMigrationVersionNumber = _versionNumberFromFile(latestMigrationFile);

    await persistentStore.createVersionTableIfNecessary();
    var currentVersion = await persistentStore.schemaVersion;

    List<File> migrationFilesToRun;
    if (currentVersion == 0) {
      migrationFilesToRun = files;
    } else if (latestMigrationVersionNumber > currentVersion) {
      var indexOfCurrent = files.indexOf(files.firstWhere((f) => _versionNumberFromFile(f) == latestMigrationVersionNumber));
      migrationFilesToRun = files.sublist(indexOfCurrent + 1);
    }

    if (migrationFilesToRun == null) {
      return false;
    }

    for (var migration in migrationFilesToRun) {
      await _executeUpgradeForFile(migration);
    }

    return true;
  }

  int _versionNumberFromFile(File file) {
    var fileName = file.uri.pathSegments.last;
    var migrationName = fileName.split(".").first;
    return int.parse(migrationName.split("_").first);
  }

  Future _executeUpgradeForFile(File file) {
    var source = _sourceWithFile(file, "upgrade");

  }

  String _sourceWithFile(File file, String command) {
    var builder = new StringBuffer();
    builder.writeln("import 'dart:async';");
    builder.writeln("import 'dart:io';");
    builder.writeln("import 'package:aqueduct/aqueduct.dart';");
    builder.writeln(file.readAsStringSync());
    builder.writeln("Future main (List<String> args, SendPort sendPort) async {");
    builder.writeln("  var migrationClassMirror = currentMirrorSystem().isolate.rootLibrary.declarations.values.firstWhere((dm) => dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration)));");
    builder.writeln("  var migrationInstance = migrationClassMirror.newInstance(new Symbol(''), []).reflectee;");
    builder.writeln("  migrationInstance.database = ;");
    builder.writeln("  await migrationInstance.$command();");
    builder.writeln("  if (!migrationInstance.database.builtSchema.matches(codebaseSchema)) {");
    builder.writeln("    throw new MigrationException(");
    builder.writeln("  }");
    builder.writeln("  var finishedSchema = await migrationInstance.database.execute();");
    builder.writeln("  sendPort.send(finishedSchema);");
    builder.writeln("}");

    return builder.toString();
  }
}

class MigrationException {
  MigrationException(this.message);
  String message;
}