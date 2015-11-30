part of monadart;

class PostgresModelAdapter extends QueryAdapter {
  static Logger logger = new Logger("monadart");

  PostgresqlSchema schema;
  Connection _databaseConnection;
  Function connectFunction;

  PostgresModelAdapter(this.schema, this.connectFunction);

  PostgresModelAdapter.fromConnectionInfo(
      this.schema, String username, String password, String host, int port, String databaseName,
      {String timezone: "UTC"}) {
    var uri = "postgres://$username:$password@$host:$port/$databaseName";
    this.connectFunction = () async {
      logger.info("Inquirer: PostgresqlModelAdapter connecting, $username@$host:$port/$databaseName.");
      return await connect(uri, timeZone: timezone);
    };
  }

  Future<Connection> getDatabaseConnection() async {
    if (_databaseConnection == null || _databaseConnection.state == ConnectionState.closed) {
      if (connectFunction == null) {
        throw new QueryException(503, "Could not connect to database, no connect function.", 1);
      }
      try {
        _databaseConnection = await connectFunction();
      } catch (e) {
        throw new QueryException(503, "Could not connect to database ${e}", 1);
      }
    }

    return _databaseConnection;
  }

  @override
  void close() {
    if (_databaseConnection != null) {
      _databaseConnection.close();
      _databaseConnection = null;
    }
  }

  @override
  Future run(String format, {Map<String, dynamic> values}) {
    return new Future(() async {
      Connection conn = await getDatabaseConnection();
      var result = await conn.query(format, values).toList();

      return result;
    });
  }

  @override
  Future<dynamic> execute(Query query) {
    PostgresqlQuery pgsqlQuery = null;
    switch (query.queryType) {
      case QueryType.fetch:
        pgsqlQuery = new PostgresqlFetchQuery(schema, query);
        break;
      case QueryType.count:
//        query = new PostgresqlFetchQuery(schema, req);
        break;
      case QueryType.delete:
        pgsqlQuery = new PostgresqlDeleteQuery(schema, query);
        break;
      case QueryType.insert:
        pgsqlQuery = new PostgresqlInsertQuery(schema, query);
        break;
      case QueryType.update:
        pgsqlQuery = new PostgresqlUpdateQuery(schema, query);
        break;
    }

    return new Future(() async {
      logger.info("Inquirer: Executing ${pgsqlQuery.string} ${pgsqlQuery.values}");

      try {
        var conn = await getDatabaseConnection();

        if (pgsqlQuery.query.queryType == QueryType.fetch ||
            pgsqlQuery.query.queryType == QueryType.update ||
            pgsqlQuery.query.queryType == QueryType.insert) {
          var result = await conn.query(pgsqlQuery.string, pgsqlQuery.values).toList();

          logger.info("Inquirer: Received $result");

          return mapRowsAccordingToQuery(result, pgsqlQuery);
        } else {
          return await conn.execute(pgsqlQuery.string, pgsqlQuery.values);
        }
      } on PostgresqlException catch (e, stackTrace) {
        throw interpretException(e, stackTrace);
      } on QueryException {
        rethrow;
      } catch (e, stackTrace) {
        throw new QueryException(500, e.toString(), -1, stackTrace: stackTrace);
      }
    });
  }

  Exception interpretException(PostgresqlException exception, StackTrace stackTrace) {
    ServerMessage msg = exception.serverMessage;
    if (msg == null) {
      return new QueryException(500, exception.message, 0, stackTrace: stackTrace);
    }

    switch (msg.code) {
      case "42703":
        return new QueryException(400, exception.message, 42703, stackTrace: stackTrace);
      case "23505":
        return new QueryException(409, exception.message, 23505, stackTrace: stackTrace);
      case "23502":
        return new QueryException(400, exception.message, 23502, stackTrace: stackTrace);
      case "23503":
        return new QueryException(400, exception.message, 23503, stackTrace: stackTrace);
    }

    return new QueryException(500, exception.message, 0, stackTrace: stackTrace);
  }

  List<Model> mapRowsAccordingToQuery(List<Row> rows, PostgresqlQuery query) {
    ClassMirror m = reflectClass(query.query.modelType);
    var table = schema.tables[query.query.modelType];

    return rows.map((row) {
      var instance = m.newInstance(new Symbol(""), []).reflectee;

      var map = new Map.fromIterables(query.resultMappingElements.map((m) => m.modelKey), row.toList());

      // Replace any foreign keys with embedded object
      query.resultMappingElements.forEach((e) {
        var column = table.columns[e.modelKey];
        var value = map[e.modelKey];
        if (column.relationship != null && value != null) {
          var innerKey = column.relationship.destinationModelKey;

          var innerMap = {innerKey: value};
          var innerModel = reflectClass(column.relationship.destinationType).newInstance(new Symbol(""), []).reflectee;
          mapToModel(innerModel, innerMap);

          map[e.modelKey] = innerModel;
        }
      });

      mapToModel(instance, map);

      return instance;
    }).toList();
  }

  void mapToModel(Model object, Map<String, dynamic> values) {
    values.forEach((k, v) {
      object.dynamicBacking[k] = v;
    });
  }
}
