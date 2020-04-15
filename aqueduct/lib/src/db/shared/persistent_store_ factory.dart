import 'package:logging/logging.dart';
import 'package:safe_config/safe_config.dart';
import 'package:aqueduct/src/db/mysql/mysql_persistent_store.dart';
import 'package:aqueduct/src/db/postgresql/postgresql_persistent_store.dart';
import 'package:aqueduct/src/db/persistent_store/persistent_store.dart';

class PersistentStoreConnection {
  PersistentStoreConnection(this.schema, this.username, this.password,
      this.host, this.port, this.databaseName,
      {this.useSSL = false, this.timeZone = "UTC"});

  PersistentStoreConnection.fromConfig(
      String schema, DatabaseConfiguration config,
      {bool useSSL = false, String timeZone = "UTC"})
      : this(schema, config.username, config.password, config.host, config.port,
            config.databaseName,
            useSSL: useSSL, timeZone: timeZone);

  final String schema;
  final String username;
  final String password;
  final String host;
  final int port;
  final String databaseName;
  final bool useSSL;
  final String timeZone;

  void setLogger(Level level, Function record) {
    if (schema == "postgres") {
      PostgreSQLPersistentStore.logger.level = level;
      PostgreSQLPersistentStore.logger.onRecord
          .listen((r) => record("${r.message}"));
    } else if (schema == "mysql") {
      MySqlPersistentStore.logger.level = level;
      MySqlPersistentStore.logger.onRecord
          .listen((r) => record("${r.message}"));
    } else {
      throw Exception("not support database of '$schema'");
    }
  }

  PersistentStore _persistentStore;
  PersistentStore get persistentStore {
    if (_persistentStore != null) {
      return _persistentStore;
    }
    if (schema == "postgres") {
      _persistentStore = PostgreSQLPersistentStore(
          username, password, host, port, databaseName,
          useSSL: useSSL);
    } else if (schema == "mysql") {
      _persistentStore = MySqlPersistentStore(
          username, password, host, port, databaseName,
          useSSL: useSSL);
    } else {
      throw Exception("not support database of '$schema'");
    }
    return _persistentStore;
  }
}


