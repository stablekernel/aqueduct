import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/schema/migration_source.dart';
import 'package:isolate_executor/isolate_executor.dart';

class RunUpgradeExecutable extends Executable<Map<String, dynamic>> {
  RunUpgradeExecutable(Map<String, dynamic> message)
      : inputSchema = new Schema.fromMap(message["schema"] as Map<String, dynamic>),
        dbInfo = new DBInfo.fromMap(message["dbInfo"] as Map<String, dynamic>),
        sources = (message["migrations"] as List<Map>)
            .map((m) => new MigrationSource.fromMap(m as Map<String, dynamic>))
            .toList(),
        currentVersion = message["currentVersion"] as int,
        super(message);

  RunUpgradeExecutable.input(this.inputSchema, this.dbInfo, this.sources, this.currentVersion)
      : super({
          "schema": inputSchema.asMap(),
          "dbInfo": dbInfo.asMap(),
          "migrations": sources.map((source) => source.asMap()).toList(),
          "currentVersion": currentVersion
        });

  final Schema inputSchema;
  final DBInfo dbInfo;
  final List<MigrationSource> sources;
  final int currentVersion;

  @override
  Future<Map<String, dynamic>> execute() async {
    hierarchicalLoggingEnabled = true;

    PostgreSQLPersistentStore.logger.level = Level.ALL;
    PostgreSQLPersistentStore.logger.onRecord.listen((r) => log("${r.message}"));

    PersistentStore store;
    if (dbInfo != null && dbInfo.flavor == "postgres") {
      store = new PostgreSQLPersistentStore(
          dbInfo.username, dbInfo.password, dbInfo.host, dbInfo.port, dbInfo.databaseName,
          timeZone: dbInfo.timeZone);
    }

    var migrationTypes = currentMirrorSystem()
        .isolate
        .rootLibrary
        .declarations
        .values
        .where((dm) => dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration)));

    final instances = sources.map((s) {
      final type = migrationTypes.firstWhere((cm) {
        return cm is ClassMirror && MirrorSystem.getName(cm.simpleName) == s.name;
      }) as ClassMirror;
      final migration = type.newInstance(const Symbol(""), []).reflectee as Migration;
      migration.version = s.versionNumber;
      return migration;
    }).toList();

    final updatedSchema = await store.upgrade(inputSchema, instances);
    await store.close();

    return updatedSchema.asMap();
  }

  static List<String> get imports => [
        "package:aqueduct/aqueduct.dart",
        "package:logging/logging.dart",
        "package:aqueduct/src/db/schema/migration_source.dart"
      ];
}

class DBInfo {
  DBInfo(this.flavor, this.username, this.password, this.host, this.port, this.databaseName, this.timeZone);

  DBInfo.fromMap(Map<String, dynamic> map)
      : flavor = map["flavor"] as String,
        username = map["username"] as String,
        password = map["password"] as String,
        host = map["host"] as String,
        port = map["port"] as int,
        databaseName = map["databaseName"] as String,
        timeZone = map["timeZone"] as String;

  final String flavor;
  final String username;
  final String password;
  final String host;
  final int port;
  final String databaseName;
  final String timeZone;

  Map<String, dynamic> asMap() {
    return {
      "flavor": flavor,
      "username": username,
      "password": password,
      "host": host,
      "port": port,
      "databaseName": databaseName,
      "timeZone": timeZone
    };
  }
}
