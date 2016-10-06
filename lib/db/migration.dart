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

  Future _executeUpgradeForFile(File file) async {
    var source = _upgradeSourceWithFile(file);

  }

  String _upgradeSourceWithFile(File file) {
    var f = (List<String> args, SendPort sendPort) async {
      var migrationClassMirror = currentMirrorSystem().isolate.rootLibrary.declarations.values.firstWhere((dm) => dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration))) as ClassMirror;
      var migrationInstance = migrationClassMirror.newInstance(new Symbol(''), []).reflectee as Migration;
      migrationInstance.database = null;

      await migrationInstance.upgrade();
      await migrationInstance.database.execute();
      var outSchema = migrationInstance.currentSchema;
      sendPort.send(outSchema.asMap());
    };

    var source = (reflect(f) as ClosureMirror).function.source;
    var builder = new StringBuffer();
    builder.writeln(file.readAsStringSync());
    builder.writeln("");
    builder.writeln("Future main (List<String> args, SendPort sendPort) async {");
    builder.writeln(source);
    builder.writeln("}");

    return builder.toString();
  }
}

class MigrationException {
  MigrationException(this.message);
  String message;
}