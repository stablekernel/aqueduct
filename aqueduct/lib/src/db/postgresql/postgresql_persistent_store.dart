import 'dart:async';

import 'package:aqueduct/src/application/service_registry.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

import '../managed/managed.dart';
import '../persistent_store/persistent_store.dart';
import '../postgresql/postgresql_query.dart';
import '../query/query.dart';
import '../schema/schema.dart';
import 'postgresql_schema_generator.dart';

/// The database layer responsible for carrying out [Query]s against PostgreSQL databases.
///
/// To interact with a PostgreSQL database, a [ManagedContext] must have an instance of this class.
/// Instances of this class are configured to connect to a particular PostgreSQL database.
class PostgreSQLPersistentStore extends PersistentStore
    with PostgreSQLSchemaGenerator {
  /// Creates an instance of this type from connection info.
  PostgreSQLPersistentStore(
      this.username, this.password, this.host, this.port, this.databaseName,
      {this.timeZone = "UTC", bool useSSL = false})
      : isSSLConnection = useSSL {
    ServiceRegistry.defaultInstance
        .register<PostgreSQLPersistentStore>(this, (store) => store.close());
  }

  /// Same constructor as default constructor.
  ///
  /// Kept for backwards compatability.
  PostgreSQLPersistentStore.fromConnectionInfo(
      this.username, this.password, this.host, this.port, this.databaseName,
      {this.timeZone = "UTC", bool useSSL = false})
      : isSSLConnection = useSSL {
    ServiceRegistry.defaultInstance
        .register<PostgreSQLPersistentStore>(this, (store) => store.close());
  }

  PostgreSQLPersistentStore._from(PostgreSQLPersistentStore from)
      : isSSLConnection = from.isSSLConnection,
        username = from.username,
        password = from.password,
        host = from.host,
        port = from.port,
        databaseName = from.databaseName,
        timeZone = from.timeZone;

  factory PostgreSQLPersistentStore._transactionProxy(
      PostgreSQLPersistentStore parent, PostgreSQLExecutionContext ctx) {
    return _TransactionProxy(parent, ctx);
  }

  /// The logger used by instances of this class.
  static Logger logger = Logger("aqueduct");

  /// The username of the database user for the database this instance connects to.
  final String username;

  /// The password of the database user for the database this instance connects to.
  final String password;

  /// The host of the database this instance connects to.
  final String host;

  /// The port of the database this instance connects to.
  final int port;

  /// The name of the database this instance connects to.
  final String databaseName;

  /// The time zone of the connection to the database this instance connects to.
  final String timeZone;

  /// Whether this connection is established over SSL.
  final bool isSSLConnection;

  /// Whether or not the underlying database connection is open.
  ///
  /// Connections are automatically opened when a query is executed, so this property should not be used
  /// under normal operation. See [getDatabaseConnection].
  bool get isConnected {
    if (_databaseConnection == null) {
      return false;
    }

    return !_databaseConnection.isClosed;
  }

  /// Amount of time to wait before connection fails to open.
  ///
  /// Defaults to 30 seconds.
  final Duration connectTimeout = Duration(seconds: 30);

  PostgreSQLConnection _databaseConnection;
  Completer<PostgreSQLConnection> _pendingConnectionCompleter;

  /// Retrieves a connection to the database this instance connects to.
  ///
  /// If no connection exists, one will be created. A store will have no more than one connection at a time.
  /// You should rarely need to access this connection directly.
  Future<PostgreSQLConnection> getDatabaseConnection() async {
    if (_databaseConnection == null || _databaseConnection.isClosed) {
      if (_pendingConnectionCompleter == null) {
        _pendingConnectionCompleter = Completer<PostgreSQLConnection>();

        // ignore: unawaited_futures
        _connect().timeout(connectTimeout).then((conn) {
          _databaseConnection = conn;
          _pendingConnectionCompleter.complete(_databaseConnection);
          _pendingConnectionCompleter = null;
        }).catchError((e) {
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

  Future<PostgreSQLExecutionContext> get _executionContext async =>
      getDatabaseConnection();

  @override
  Query<T> newQuery<T extends ManagedObject>(
      ManagedContext context, ManagedEntity entity) {
    return PostgresQuery<T>.withEntity(context, entity);
  }

  @override
  Future<dynamic> execute(String sql,
      {Map<String, dynamic> substitutionValues, Duration timeout}) async {
    timeout ??= Duration(seconds: 30);
    var now = DateTime.now().toUtc();
    var dbConnection = await _executionContext;
    try {
      var rows = await dbConnection.query(sql,
          substitutionValues: substitutionValues,
          timeoutInSeconds: timeout.inSeconds);

      var mappedRows = rows.map((row) => row.toList()).toList();
      logger.finest(() =>
          "Query:execute (${DateTime.now().toUtc().difference(now).inMilliseconds}ms) $sql -> $mappedRows");
      return mappedRows;
    } on PostgreSQLException catch (e) {
      final interpreted = _interpretException(e);
      if (interpreted != null) {
        throw interpreted;
      }

      rethrow;
    }
  }

  @override
  Future close() async {
    await _databaseConnection?.close();
    _databaseConnection = null;
  }

  @override
  Future<T> transaction<T>(ManagedContext transactionContext,
      Future<T> transactionBlock(ManagedContext transaction)) async {
    final dbConnection = await getDatabaseConnection();

    T output;
    Rollback rollback;
    try {
      await dbConnection.transaction((dbTransactionContext) async {
        transactionContext.persistentStore =
            PostgreSQLPersistentStore._transactionProxy(
                this, dbTransactionContext);

        try {
          output = await transactionBlock(transactionContext);
        } on Rollback catch (e) {
          rollback = e;
          dbTransactionContext.cancelTransaction(reason: rollback.reason);
        }
      });
    } on PostgreSQLException catch (e) {
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
    } on PostgreSQLException catch (e) {
      if (e.code == PostgreSQLErrorCode.undefinedTable) {
        return 0;
      }
      rethrow;
    }
  }

  @override
  Future<Schema> upgrade(Schema fromSchema, List<Migration> withMigrations,
      {bool temporary = false}) async {
    var connection = await getDatabaseConnection();

    Schema schema = fromSchema;
    await connection.transaction((ctx) async {
      final transactionStore =
          PostgreSQLPersistentStore._transactionProxy(this, ctx);
      await _createVersionTableIfNecessary(ctx, temporary);

      withMigrations.sort((m1, m2) => m1.version.compareTo(m2.version));

      for (var migration in withMigrations) {
        migration.database =
            SchemaBuilder(transactionStore, schema, isTemporary: temporary);
        migration.database.store = transactionStore;

        var existingVersionRows = await ctx.query(
            "SELECT versionNumber, dateOfUpgrade FROM $versionTableName WHERE versionNumber >= @v:int4",
            substitutionValues: {"v": migration.version});
        if (existingVersionRows.isNotEmpty) {
          final date = existingVersionRows.first.last;
          throw MigrationException(
              "Trying to upgrade database to version ${migration.version}, but that migration has already been performed on $date.");
        }

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
            "INSERT INTO $versionTableName (versionNumber, dateOfUpgrade) VALUES (${migration.version}, '${DateTime.now().toUtc().toIso8601String()}')");

        logger
            .info("Applied schema version ${migration.version} successfully.");

        schema = migration.currentSchema;
      }
    });

    return schema;
  }

  @override
  Future<dynamic> executeQuery(
      String formatString, Map<String, dynamic> values, int timeoutInSeconds,
      {PersistentStoreQueryReturnType returnType =
          PersistentStoreQueryReturnType.rows}) async {
    var now = DateTime.now().toUtc();
    try {
      var dbConnection = await _executionContext;
      dynamic results;

      if (returnType == PersistentStoreQueryReturnType.rows) {
        results = await dbConnection.query(formatString,
            substitutionValues: values, timeoutInSeconds: timeoutInSeconds);
      } else {
        results = await dbConnection.execute(formatString,
            substitutionValues: values, timeoutInSeconds: timeoutInSeconds);
      }

      logger.fine(() =>
          "Query (${DateTime.now().toUtc().difference(now).inMilliseconds}ms) $formatString Substitutes: ${values ?? "{}"} -> $results");

      return results;
    } on TimeoutException catch (e) {
      throw QueryException.transport("timed out connection to database",
          underlyingException: e);
    } on PostgreSQLException catch (e) {
      logger.fine(() =>
          "Query (${DateTime.now().toUtc().difference(now).inMilliseconds}ms) $formatString $values");
      final interpreted = _interpretException(e);
      if (interpreted != null) {
        throw interpreted;
      }

      rethrow;
    }
  }

  QueryException<PostgreSQLException> _interpretException(
      PostgreSQLException exception) {
    switch (exception.code) {
      case PostgreSQLErrorCode.uniqueViolation:
        return QueryException.conflict("entity_already_exists",
            ["${exception.tableName}.${exception.columnName}"],
            underlyingException: exception);
      case PostgreSQLErrorCode.notNullViolation:
        return QueryException.input("non_null_violation",
            ["${exception.tableName}.${exception.columnName}"],
            underlyingException: exception);
      case PostgreSQLErrorCode.foreignKeyViolation:
        return QueryException.input("foreign_key_violation",
            ["${exception.tableName}.${exception.columnName}"],
            underlyingException: exception);
    }

    return null;
  }

  Future _createVersionTableIfNecessary(
      PostgreSQLExecutionContext context, bool temporary) async {
    final table = versionTable;
    final commands = createTable(table, isTemporary: temporary);
    final exists = await context.query("SELECT to_regclass(@tableName:text)",
        substitutionValues: {"tableName": table.name});

    if (exists.first.first != null) {
      return;
    }

    logger.info("Initializating database...");
    for (var cmd in commands) {
      logger.info("\t$cmd");
      await context.execute(cmd);
    }
  }

  Future<PostgreSQLConnection> _connect() async {
    logger.info("PostgreSQL connecting, $username@$host:$port/$databaseName.");
    final connection = PostgreSQLConnection(host, port, databaseName,
        username: username,
        password: password,
        timeZone: timeZone,
        useSSL: isSSLConnection);
    try {
      await connection.open();
    } catch (e) {
      await connection.close();
      rethrow;
    }

    return connection;
  }
}

/// Commonly used error codes from PostgreSQL.
///
/// When a [QueryException.underlyingException] is a [PostgreSQLException], this [PostgreSQLException.code]
/// value may be one of the static properties declared in this class.
class PostgreSQLErrorCode {
  static const String duplicateTable = "42P07";
  static const String undefinedTable = "42P01";
  static const String undefinedColumn = "42703";
  static const String uniqueViolation = "23505";
  static const String notNullViolation = "23502";
  static const String foreignKeyViolation = "23503";
}

class _TransactionProxy extends PostgreSQLPersistentStore {
  _TransactionProxy(this.parent, this.context) : super._from(parent);

  final PostgreSQLPersistentStore parent;
  final PostgreSQLExecutionContext context;

  @override
  Future<PostgreSQLExecutionContext> get _executionContext async => context;
}
