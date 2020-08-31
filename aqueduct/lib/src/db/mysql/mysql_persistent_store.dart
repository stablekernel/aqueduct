import 'dart:async';
import 'package:aqueduct/aqueduct.dart';

import 'package:sqljocky5/connection/connection.dart';
import 'package:sqljocky5/sqljocky.dart';

import 'mysql_errorcode.dart';
import 'mysql_query.dart';
import 'mysql_schema_generator.dart';
import 'utils.dart';

class MySqlPersistentStore extends PersistentStore with MySqlSchemaGenerator {
  MySqlPersistentStore(String username, String password, String host, int port,
      String databaseName, {bool useSSL = false})
      : connectionSettings = ConnectionSettings(
            host: host,
            port: port,
            user: username,
            password: password,
            db: databaseName,
            useSSL: useSSL);

  factory MySqlPersistentStore._transactionProxy(
      MySqlPersistentStore parent, Querier ctx) {
    return _TransactionProxy(parent, ctx);
  }
  MySqlPersistentStore._from(MySqlPersistentStore from)
      : connectionSettings = from.connectionSettings;

  static Logger logger = Logger("aqueduct_mysql");

  final ConnectionSettings connectionSettings;

  @override
  String get databaseName => connectionSettings?.db;

  MySqlConnection _databaseConnection;
  Completer<MySqlConnection> _pendingConnectionCompleter;

  bool get isConnected {
    if (_databaseConnection == null) {
      return false;
    }
    return !_isClosed;
  }

  bool _isClosed = true;

  Future<MySqlConnection> getDatabaseConnection() async {
    if (_databaseConnection == null || _isClosed) {
      if (_pendingConnectionCompleter == null) {
        _pendingConnectionCompleter = Completer<MySqlConnection>();

        MySqlConnection.connect(connectionSettings).then((conn) {
          _databaseConnection = conn;
          _pendingConnectionCompleter.complete(_databaseConnection);
          _pendingConnectionCompleter = null;
          _isClosed = false;
        }).catchError((e) {
          _isClosed = true;
          _databaseConnection?.close();
          _pendingConnectionCompleter.completeError(QueryException.transport(
              "unable to connect to database",
              underlyingException: e));
          _pendingConnectionCompleter = null;
        });
      }

      return _pendingConnectionCompleter.future;
    }

    return _databaseConnection;
  }

  @override
  Future close() async {
    await _databaseConnection?.close();
    _isClosed = true;
    _databaseConnection = null;
  }

  @override
  Future<dynamic> execute(String sql,
      {Map<String, dynamic> substitutionValues}) async {
    var now = DateTime.now().toUtc();
    var dbConnection = await executionContext;

    try {
      var rows = (substitutionValues != null && substitutionValues.isNotEmpty)
          ? (await dbConnection.prepared(
              sql, MySqlUtils.getMySqlVariables(sql, substitutionValues)))
          : (await dbConnection.execute(sql));
      // timeoutInSeconds: timeout.inSeconds);

      var mappedRows = await rows.map((row) => row.toList()).toList();
      logger.finest(() =>
          "Query:execute (${DateTime.now().toUtc().difference(now).inMilliseconds}ms) $sql -> $mappedRows");
      return mappedRows;
    } on MySqlException catch (e) {
      final interpreted = _interpretException(e);
      if (interpreted != null) {
        throw interpreted;
      }

      rethrow;
    }
  }

  @override
  Future<dynamic> executeQuery(
      String formatString, Map<String, dynamic> values, int timeoutInSeconds,
      {PersistentStoreQueryReturnType returnType}) async {
    var now = DateTime.now().toUtc();
    try {
      var dbConnection = await executionContext;
      StreamedResults results;
      List<dynamic> paramValues =
          MySqlUtils.getMySqlVariables(formatString, values);
      // print(formatString);
      // print(values?.keys);
      // print(values?.values);
      // print(paramValues);

      if (returnType == PersistentStoreQueryReturnType.rows) {
        results = await dbConnection
            .prepared(formatString, paramValues)
            .timeout(Duration(seconds: timeoutInSeconds));
      } else {
        if (values != null && values.isNotEmpty) {
          results = await dbConnection
              .prepared(formatString, paramValues)
              .timeout(Duration(seconds: timeoutInSeconds));
        } else {
          results = await dbConnection
              .execute(formatString)
              .timeout(Duration(seconds: timeoutInSeconds));
        }
      }

      logger.fine(() =>
          "Query (${DateTime.now().toUtc().difference(now).inMilliseconds}ms) $formatString Substitutes: ${values ?? "{}"} -> $results");

      return results;
    } on TimeoutException catch (e) {
      throw QueryException.transport("timed out connection to database",
          underlyingException: e);
    } on MySqlException catch (e) {
      print(e.runtimeType);
      logger.fine(() =>
          "Query (${DateTime.now().toUtc().difference(now).inMilliseconds}ms) $formatString $values");
      logger.warning(() => e.toString());
      final interpreted = _interpretException(e);
      if (interpreted != null) {
        throw interpreted;
      }

      rethrow;
    }
  }

  @override
  Query<T> newQuery<T extends ManagedObject>(
      ManagedContext context, ManagedEntity entity,
      {T values}) {
    final query = MySqlQuery<T>.withEntity(context, entity);
    if (values != null) {
      query.values = values;
    }
    return query;
  }

  @override
  Future<int> get schemaVersion async {
    try {
      var values = await execute(
              "SELECT versionNumber, dateOfUpgrade FROM $versionTableName ORDER BY dateOfUpgrade ASC")
          as List<List<dynamic>>;
      if (values.isEmpty) {
        return 0;
      }

      final version = await values.last.first;
      return version as int;
    } on MySqlException catch (e) {
      logger.info("e.errorNumber=${e.errorNumber}");
      if (e.errorNumber == MySqlErrorCode.table_existed.code) {
        // 1146:table is not exist;
        return 0;
      }
      rethrow;
    }
  }

  @override
  Future<T> transaction<T>(ManagedContext transactionContext,
      Future<T> Function(ManagedContext transaction) transactionBlock) async {
    final dbConnection = await getDatabaseConnection();

    T output;
    Rollback rollback;
    try {
      await dbConnection.transaction((dbTransactionContext) async {
        transactionContext.persistentStore =
            MySqlPersistentStore._transactionProxy(this, dbTransactionContext);

        try {
          output = await transactionBlock(transactionContext);
        } on Rollback catch (e) {
          rollback = e;
        await  dbTransactionContext.rollback();
          // dbTransactionContext.cancelTransaction(reason: rollback.reason);
        }
      });
    } on MySqlException catch (e) {
      final interpreted = _interpretException(e);
      if (interpreted != null) {
        throw interpreted;
      }

      rethrow;
    }

    if (rollback != null) {
      throw rollback;
    }

    return output;
  }

  @override
  Future<Schema> upgrade(Schema fromSchema, List<Migration> withMigrations,
      {bool temporary = false}) async {
    var connection = await getDatabaseConnection();

    Schema schema = fromSchema;

    await connection.transaction((ctx) async {
      final transactionStore =
          MySqlPersistentStore._transactionProxy(this, ctx);
      await _createVersionTableIfNecessary(ctx, temporary);

      withMigrations.sort((m1, m2) => m1.version.compareTo(m2.version));

      for (var migration in withMigrations) {
        migration.database =
            SchemaBuilder(transactionStore, schema, isTemporary: temporary);
        migration.database.store = transactionStore;

        StreamedResults existingVersionRows = await ctx.prepared(
            "SELECT `versionNumber`, `dateOfUpgrade` FROM $versionTableName WHERE `versionNumber` >= ?",
            [migration.version]);

        await existingVersionRows.forEach((row) {
          final date = row.last;
          throw MigrationException(
              "Trying to upgrade database to version ${migration.version}, but that migration has already been performed on $date.");
        });
        logger.info("Applying migration version ${migration.version}...");
        await migration.upgrade();

        for (var cmd in migration.database.commands) {
          logger.info("\t$cmd");
          await ctx.execute(cmd);
        }

        logger.info(
            "Seeding data from migration version ${migration.version}...");
        await migration.seed();

        await ctx.execute(
            "INSERT INTO `$versionTableName` (`versionNumber`, `dateOfUpgrade`) VALUES (${migration.version}, '${DateTime.now().toLocal().toIso8601String()}')");

        logger
            .info("Applied schema version ${migration.version} successfully.");

        schema = migration.currentSchema;
      }
    });

    return schema;
  }

  QueryException<MySqlException> _interpretException(MySqlException exception) {
    if (exception.errorNumber == MySqlErrorCode.uniqueViolation.code) {
      return QueryException.conflict(
          "entity_already_exists", [exception.message],
          underlyingException: exception);
    } else if (exception.errorNumber == MySqlErrorCode.notNullViolation.code ||
        exception.errorNumber == MySqlErrorCode.notDefaultValueViolation.code) {
      return QueryException.input("non_null_violation", [exception.message],
          underlyingException: exception);
    } else if (exception.errorNumber ==
            MySqlErrorCode.foreignKeyViolation.code ||
        exception.errorNumber == MySqlErrorCode.foreignKeyViolation1.code) {
      return QueryException.input("foreign_key_violation", [exception.message],
          underlyingException: exception);
    }
    return null;
  }

  Future _createVersionTableIfNecessary(Querier context, bool temporary) async {
    final table = versionTable;
    final commands = createTable(table, isTemporary: temporary);

    final exists = await context.prepared(
        "select count(*)  from information_schema.TABLES t where t.TABLE_SCHEMA =? and t.TABLE_NAME =?",
        [databaseName, table.name]);
    Row result = await exists.first;
    if ((result != null) && (result.first as int) > 0) {
      return;
    }

    logger.info("Initializating database...");
    for (var cmd in commands) {
      logger.info("\t$cmd");
      await context.execute(cmd);
    }
  }

  Future<Querier> get executionContext => getDatabaseConnection();
}

class _TransactionProxy extends MySqlPersistentStore {
  _TransactionProxy(this.parent, this.context) : super._from(parent);

  final MySqlPersistentStore parent;
  final Querier context;

  @override
  Future<Querier> get executionContext async => context;
}
