import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import '../managed/managed.dart';
import '../persistent_store/persistent_store.dart';
import 'schema.dart';
import '../../utilities/source_generator.dart';
import '../postgresql/postgresql_persistent_store.dart';

/// Thrown when [Migration] encounters an error.
class MigrationException {
  MigrationException(this.message);
  String message;

  String toString() => message;
}

/// The base class for migration instructions.
///
/// For each set of changes to a database, a subclass of [Migration] is created.
/// Subclasses will override [upgrade] to make changes to the [Schema] which
/// are translated into database operations to update a database's schema.
abstract class Migration {
  /// The current state of the [Schema].
  ///
  /// During migration, this value will be modified as [SchemaBuilder] operations
  /// are executed. See [SchemaBuilder].
  Schema get currentSchema => database.schema;

  /// The [PersistentStore] that represents the database being migrated.
  PersistentStore get store => database.store;

  /// Receiver for database altering operations.
  ///
  /// Methods invoked on this instance - such as [SchemaBuilder.createTable] - will be validated
  /// and generate the appropriate SQL commands to apply to a database to alter its schema.
  SchemaBuilder database;

  /// Method invoked to upgrade a database to this migration version.
  ///
  /// Subclasses will override this method and invoke methods on [database] to upgrade
  /// the database represented by [store].
  Future upgrade();

  /// Method invoked to downgrade a database from this migration version.
  ///
  /// Subclasses will override this method and invoke methods on [database] to downgrade
  /// the database represented by [store].
  Future downgrade();

  /// Method invoked to seed a database's data after this migration version is upgraded to.
  ///
  /// Subclasses will override this method and invoke query methods on [store] to add data
  /// to a database after this migration version is executed.
  Future seed();
}

/// Executes migrations.
///
/// This class is used by the migration process and shouldn't be used directly.
class MigrationExecutor {
  MigrationExecutor(this.persistentStore, this.projectDirectoryPath,
      this.libraryName, this.migrationFileDirectory);

  PersistentStore persistentStore;
  Uri migrationFileDirectory;
  Uri projectDirectoryPath;
  String libraryName;

  List<File> get migrationFiles {
    var dir = new Directory.fromUri(migrationFileDirectory);

    Map<int, File> orderMap = dir
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
        throw new MigrationException(
            "Migration files must have the following format: Version_Name.migration.dart,"
            "where Version must be an integer (optionally prefixed with 0s, e.g. '00000002')"
            " and '_Name' is optional. Offender: ${fse.uri}");
      }
    });

    var sortedKeys = (new List.from(orderMap.keys));
    sortedKeys.sort((int a, int b) => a.compareTo(b));
    return sortedKeys.map((v) => orderMap[v]).toList();
  }

  Future<Schema> validate() async {
    var directory = new Directory.fromUri(migrationFileDirectory);
    if (!directory.existsSync()) {
      throw new MigrationException(
          "Migration directory doesn't exist, nothing to validate.");
    }

    var files = migrationFiles;
    if (files.isEmpty) {
      throw new MigrationException(
          "Migration directory doesn't contain any migrations, nothing to validate.");
    }

    var generator = new SourceGenerator(
        (List<String> args, Map<String, dynamic> values) async {
      var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
      var schema = new Schema.fromDataModel(dataModel);

      return schema.asMap();
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName",
      "dart:isolate",
      "dart:mirrors",
      "dart:async"
    ]);

    var executor = new IsolateExecutor(generator, [libraryName],
        packageConfigURI: projectDirectoryPath.resolve(".packages"));
    var projectSchema = new Schema.fromMap(await executor.execute(
        workingDirectory: projectDirectoryPath) as Map<String, dynamic>);

    var schema = new Schema.empty();
    for (var migration in migrationFiles) {
      schema = await _executeUpgradeForFile(migration, schema, dryRun: true);
    }

    var errors = <String>[];
    var matches = schema.matches(projectSchema, errors);

    if (!matches) {
      throw new MigrationException(
          "Validation failed:\n\t${errors.join("\n\t")}");
    }

    return schema;
  }

  Future<File> generate() async {
    _createMigrationDirectoryIfNecessary();
    _ensurePackageResolutionAvailable();

    var files = migrationFiles;
    if (!files.isEmpty) {
      // For now, just make a new empty one...
      var newVersionNumber = versionNumberFromFile(files.last) + 1;
      var contents = SchemaBuilder.sourceForSchemaUpgrade(
          new Schema.empty(), new Schema.empty(), newVersionNumber);
      var file = new File.fromUri(migrationFileDirectory.resolve(
          "${"$newVersionNumber".padLeft(8, "0")}_Unnamed.migration.dart"));
      file.writeAsStringSync(contents);

      return file;
    }

    var generator = new SourceGenerator(
        (List<String> args, Map<String, dynamic> values) async {
      var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
      var schema = new Schema.fromDataModel(dataModel);

      return SchemaBuilder.sourceForSchemaUpgrade(
          new Schema.empty(), schema, 1);
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName",
      "dart:isolate",
      "dart:mirrors",
      "dart:async"
    ]);

    var executor = new IsolateExecutor(generator, [libraryName],
        packageConfigURI: projectDirectoryPath.resolve(".packages"));
    var contents =
        await executor.execute(workingDirectory: projectDirectoryPath);
    var file = new File.fromUri(
        migrationFileDirectory.resolve("00000001_Initial.migration.dart"));
    file.writeAsStringSync(contents);

    return file;
  }

  Future<Schema> upgrade() async {
    var directory = new Directory.fromUri(migrationFileDirectory);
    if (!directory.existsSync()) {
      throw new MigrationException(
          "Migration directory doesn't exist, nothing to upgrade.");
    }

    var files = migrationFiles;
    if (files.isEmpty) {
      throw new MigrationException(
          "Migration directory doesn't contain any migrations, nothing to upgrade.");
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

  int versionNumberFromFile(File file) {
    var fileName = file.uri.pathSegments.last;
    var migrationName = fileName.split(".").first;
    return int.parse(migrationName.split("_").first);
  }

  List<List<File>> _splitMigrationFiles(int aroundVersion) {
    var files = migrationFiles;
    var latestMigrationFile = files.last;
    var latestMigrationVersionNumber =
        versionNumberFromFile(latestMigrationFile);

    List<File> migrationFilesToRun = [];
    List<File> migrationFilesToGetToCurrent = [];
    if (aroundVersion == 0) {
      migrationFilesToRun = files;
    } else if (latestMigrationVersionNumber > aroundVersion) {
      var indexOfCurrent = files.indexOf(
          files.firstWhere((f) => versionNumberFromFile(f) == aroundVersion));
      migrationFilesToGetToCurrent = files.sublist(0, indexOfCurrent + 1);
      migrationFilesToRun = files.sublist(indexOfCurrent + 1);
    } else {
      migrationFilesToGetToCurrent = files;
    }

    return [migrationFilesToGetToCurrent, migrationFilesToRun];
  }

  Future<Schema> _executeUpgradeForFile(File file, Schema schema,
      {bool dryRun: false}) async {
    var generator = new SourceGenerator(
        (List<String> args, Map<String, dynamic> values) async {
      var inputSchema =
          new Schema.fromMap(values["schema"] as Map<String, dynamic>);
      var dbInfo = values["dbInfo"];
      var dryRun = values["dryRun"];

      PersistentStore store;
      if (dbInfo != null && dbInfo["flavor"] == "postgres") {
        store = new PostgreSQLPersistentStore.fromConnectionInfo(
            dbInfo["username"],
            dbInfo["password"],
            dbInfo["host"],
            dbInfo["port"],
            dbInfo["databaseName"],
            timeZone: dbInfo["timeZone"]);
      }

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
      migrationInstance.database = new SchemaBuilder(store, inputSchema);

      await migrationInstance.upgrade();

      if (!dryRun && !migrationInstance.database.commands.isEmpty) {
        await migrationInstance.store
            .upgrade(versionNumber, migrationInstance.database.commands);
        await migrationInstance.seed();
        await migrationInstance.database.store.close();
      }

      return migrationInstance.currentSchema.asMap();
    }, imports: [
      "dart:async",
      "package:aqueduct/aqueduct.dart",
      "dart:isolate",
      "dart:mirrors"
    ], additionalContents: file.readAsStringSync());

    var executor = new IsolateExecutor(generator, [
      "${versionNumberFromFile(file)}"
    ], message: {
      "dryRun": dryRun,
      "schema": schema.asMap(),
      "dbInfo": _storeConnectionMap,
    });
    var schemaMap = await executor.execute();
    return new Schema.fromMap(schemaMap as Map<String, dynamic>);
  }

  Map<String, dynamic> get _storeConnectionMap {
    if (persistentStore is PostgreSQLPersistentStore) {
      var s = persistentStore as PostgreSQLPersistentStore;
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
