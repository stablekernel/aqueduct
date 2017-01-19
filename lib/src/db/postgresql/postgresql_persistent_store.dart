import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'dart:async';
import '../managed/managed.dart';
import '../query/query.dart';
import '../persistent_store/persistent_store.dart';
import '../schema/schema.dart';
import 'postgresql_schema_generator.dart';

/// A function that will create an opened instance of [PostgreSQLConnection] when executed.
typedef Future<PostgreSQLConnection> PostgreSQLConnectionFunction();

/// The database layer responsible for carrying out [Query]s against PostgreSQL databases.
///
/// To interact with a PostgreSQL database, a [ManagedContext] must have an instance of this class.
/// Instances of this class are configured to connect to a particular PostgreSQL database.
class PostgreSQLPersistentStore extends PersistentStore
    with PostgreSQLSchemaGenerator {
  /// The logger used by instances of this class.
  static Logger logger = new Logger("aqueduct");

  /// The function that will generate a [PostgreSQLConnection] when this instance does not have a valid one.
  PostgreSQLConnectionFunction connectFunction;

  /// The username of the database user for the database this instance connects to.
  String username;

  /// The password of the database user for the database this instance connects to.
  String password;

  /// The host of the database this instance connects to.
  String host;

  /// The port of the database this instance connects to.
  int port;

  /// The name of the database this instance connects to.
  String databaseName;

  /// The time zone of the connection to the database this instance connects to.
  String timeZone = "UTC";

  PostgreSQLConnection _databaseConnection;
  Completer<PostgreSQLConnection> _pendingConnectionCompleter;

  /// Creates an instance of this type from a manual function.
  PostgreSQLPersistentStore(this.connectFunction) : super();

  /// Creates an instance of this type from connection info.
  PostgreSQLPersistentStore.fromConnectionInfo(
      this.username, this.password, this.host, this.port, this.databaseName,
      {this.timeZone: "UTC", bool useSSL: false}) {
    this.connectFunction = () async {
      logger
          .info("PostgreSQL connecting, $username@$host:$port/$databaseName.");
      var connection = new PostgreSQLConnection(host, port, databaseName,
          username: username,
          password: password,
          timeZone: timeZone,
          useSSL: useSSL);
      try {
        await connection.open();
      } catch (e) {
        await connection?.close();
        rethrow;
      }
      return connection;
    };
  }

  /// Retrieves a connection to the database this instance connects to.
  ///
  /// If no connection exists, one will be created. A store will have no more than one connection at a time.
  /// You should rarely need to access this connection directly.
  Future<PostgreSQLConnection> getDatabaseConnection() async {
    if (_databaseConnection == null || _databaseConnection.isClosed) {
      if (connectFunction == null) {
        throw new QueryException(QueryExceptionEvent.internalFailure,
            message: "Could not connect to database, no connect function.");
      }

      if (_pendingConnectionCompleter == null) {
        _pendingConnectionCompleter = new Completer<PostgreSQLConnection>();

        connectFunction().then((conn) {
          _databaseConnection = conn;
          _pendingConnectionCompleter.complete(_databaseConnection);
          _pendingConnectionCompleter = null;
        }).catchError((e) {
          _pendingConnectionCompleter.completeError(new QueryException(
              QueryExceptionEvent.connectionFailure,
              underlyingException: e));
          _pendingConnectionCompleter = null;
        });
      }

      return _pendingConnectionCompleter.future;
    }

    return _databaseConnection;
  }

  @override
  Future<dynamic> execute(String sql,
      {Map<String, dynamic> substitutionValues}) async {
    var now = new DateTime.now().toUtc();
    var dbConnection = await getDatabaseConnection();
    try {
      var results =
          await dbConnection.query(sql, substitutionValues: substitutionValues);
      var rows = await results.toList();

      var mappedRows = rows.map((row) => row.toList()).toList();
      logger.finest(() =>
          "Query:execute (${(new DateTime.now().toUtc().difference(now).inMilliseconds)}ms) $sql -> $mappedRows");
      return mappedRows;
    } on PostgreSQLException catch (e) {
      throw _interpretException(e);
    }
  }

  @override
  Future close() async {
    await _databaseConnection?.close();
    _databaseConnection = null;
  }

  @override
  Future<int> get schemaVersion async {
    try {
      var values = await execute(
              "SELECT versionNumber, dateOfUpgrade FROM $versionTableName ORDER BY dateOfUpgrade ASC")
          as List<List<dynamic>>;
      if (values.length == 0) {
        return 0;
      }

      return values.last.first;
    } on QueryException catch (e) {
      var underlying = e.underlyingException;
      if (underlying is PostgreSQLException) {
        if (underlying.code != PostgreSQLErrorCode.undefinedTable) {
          throw _interpretException(e.underlyingException);
        }
      } else {
        throw underlying;
      }
    }

    return 0;
  }

  @override
  Future upgrade(int versionNumber, List<String> commands,
      {bool temporary: false}) async {
    await _createVersionTableIfNecessary(temporary);

    var connection = await getDatabaseConnection();

    try {
      await connection.transaction((ctx) async {
        var existingVersionRows = await ctx.query(
            "SELECT versionNumber, dateOfUpgrade FROM $versionTableName WHERE versionNumber=@v:int4",
            substitutionValues: {"v": versionNumber});
        if (existingVersionRows.length > 0) {
          var date = existingVersionRows.first.last;
          throw new MigrationException(
              "Trying to upgrade database to version $versionNumber, but that migration has already been performed on ${date}.");
        }

        for (var cmd in commands) {
          logger.info("$cmd");
          await ctx.execute(cmd);
        }

        await ctx.execute(
            "INSERT INTO $versionTableName (versionNumber, dateOfUpgrade) VALUES ($versionNumber, '${new DateTime.now().toUtc().toIso8601String()}')");
      });
    } on PostgreSQLException catch (e) {
      throw _interpretException(e);
    }
  }

  Future<dynamic> executeQuery(
      String formatString, Map<String, dynamic> values, int timeoutInSeconds,
      {PersistentStoreQueryReturnType returnType: PersistentStoreQueryReturnType.rows}) async {
    var now = new DateTime.now().toUtc();
    try {
      var dbConnection = await getDatabaseConnection();
      var results = null;

      if (returnType == PersistentStoreQueryReturnType.rows) {
        results = await dbConnection
            .query(formatString, substitutionValues: values)
            .timeout(new Duration(seconds: timeoutInSeconds));
      } else {
        results = await dbConnection
            .execute(formatString, substitutionValues: values)
            .timeout(new Duration(seconds: timeoutInSeconds));
      }

      logger.fine(() =>
          "Query (${(new DateTime.now().toUtc().difference(now).inMilliseconds)}ms) $formatString Substitutes: ${values ?? "{}"} -> $results");

      return results;
    } on TimeoutException catch (e) {
      throw new QueryException(QueryExceptionEvent.connectionFailure,
          underlyingException: e);
    } on PostgreSQLException catch (e) {
      logger.fine(() =>
          "Query (${(new DateTime.now().toUtc().difference(now).inMilliseconds)}ms) $formatString $values");
      throw _interpretException(e);
    }
  }

  QueryException _interpretException(PostgreSQLException exception) {
    switch (exception.code) {
      case PostgreSQLErrorCode.undefinedColumn:
        return new QueryException(QueryExceptionEvent.requestFailure,
            underlyingException: exception);
      case PostgreSQLErrorCode.uniqueViolation:
        return new QueryException(QueryExceptionEvent.conflict,
            underlyingException: exception);
      case PostgreSQLErrorCode.notNullViolation:
        return new QueryException(QueryExceptionEvent.requestFailure,
            underlyingException: exception);
      case PostgreSQLErrorCode.foreignKeyViolation:
        return new QueryException(QueryExceptionEvent.requestFailure,
            underlyingException: exception);
    }

    return new QueryException(QueryExceptionEvent.internalFailure,
        underlyingException: exception);
  }


  Future _createVersionTableIfNecessary(bool temporary) async {
    var conn = await getDatabaseConnection();
    var commands = createTable(versionTable, isTemporary: temporary);
    try {
      await conn.transaction((ctx) async {
        for (var cmd in commands) {
          await ctx.execute(cmd);
        }
      });
    } on PostgreSQLException catch (e) {
      if (e.code != PostgreSQLErrorCode.duplicateTable) {
        rethrow;
      }
    }
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
