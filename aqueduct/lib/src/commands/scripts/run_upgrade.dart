import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/schema/migration_source.dart';
import 'package:isolate_executor/isolate_executor.dart';

class RunUpgradeExecutable extends Executable {
  RunUpgradeExecutable(Map<String, dynamic> message)
      : inputSchema = new Schema.fromMap(message["schema"]),
        dbInfo = new DBInfo.fromMap(message["dbInfo"]),
        sources = (message["migrations"] as List<Map>).map((m) => new MigrationSource.fromMap(m)).toList(),
        currentVersion = message["currentVersion"],
        super(message);

  final Schema inputSchema;
  final DBInfo dbInfo;
  final List<MigrationSource> sources;
  final int currentVersion;

  @override
  Future<dynamic> execute() async {
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

  static Map<String, dynamic> createMessage(
          Schema inputSchema, DBInfo dbInfo, List<MigrationSource> migrations, int currentVersion) =>
      {
        "schema": inputSchema.asMap(),
        "dbInfo": dbInfo.asMap(),
        "migrations": migrations.map((ms) => ms.asMap()).toList(),
        "currentVersion": currentVersion
      };
}

class DBInfo {
  DBInfo(this.flavor, this.username, this.password, this.host, this.port, this.databaseName, this.timeZone);

  DBInfo.fromMap(Map<String, dynamic> map)
      : flavor = map["flavor"],
        username = map["username"],
        password = map["password"],
        host = map["host"],
        port = map["port"],
        databaseName = map["databaseName"],
        timeZone = map["timeZone"];

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
