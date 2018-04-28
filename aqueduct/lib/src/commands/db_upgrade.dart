import 'dart:async';

import 'package:aqueduct/src/commands/scripts/run_upgrade.dart';
import 'package:aqueduct/src/db/schema/migration_source.dart';
import 'package:isolate_executor/isolate_executor.dart';

import 'base.dart';
import 'db.dart';
import '../db/db.dart';

/// Used internally.
class CLIDatabaseUpgrade extends CLIDatabaseConnectingCommand {
  @override
  Future<int> handle() async {
    final migrations = projectMigrations;

    if (migrations.isEmpty) {
      displayInfo("No migration files.");
      displayProgress("Run 'aqueduct db generate' first.");
      return 0;
    }

    final currentVersion = await persistentStore.schemaVersion;
    final appliedMigrations = migrations.where((mig) => mig.versionNumber <= currentVersion).toList();
    final migrationsToExecute = migrations.where((mig) => mig.versionNumber > currentVersion).toList();
    if (migrationsToExecute.length == 0) {
      displayInfo("Database version is already current (version: $currentVersion).");
      return 0;
    }

    if (currentVersion == 0) {
      displayInfo("Updating to version ${migrationsToExecute.last.versionNumber} on new database...");
    } else {
      displayInfo("Updating to version ${migrationsToExecute.last.versionNumber} from version $currentVersion...");
    }

    final currentSchema = await schemaByApplyingMigrationSources(appliedMigrations);

    await executeMigrations(migrationsToExecute, currentSchema, currentVersion);

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

  Future<Schema> executeMigrations(List<MigrationSource> migrations, Schema fromSchema, int fromVersion) async {
    final schemaMap = await IsolateExecutor.executeWithType(RunUpgradeExecutable,
        packageConfigURI: packageConfigUri,
        imports: RunUpgradeExecutable.imports,
        additionalContents: MigrationSource.combine(migrations),
        message: RunUpgradeExecutable.createMessage(fromSchema, _storeConnectionInfo, migrations, fromVersion),
        additionalTypes: [DBInfo], logHandler: displayProgress);

    return new Schema.fromMap(schemaMap);
  }

  DBInfo get _storeConnectionInfo {
    var s = persistentStore;
    if (s is PostgreSQLPersistentStore) {
      return new DBInfo("postgres", s.username, s.password, s.host, s.port, s.databaseName, s.timeZone);
    }

    return null;
  }
}
