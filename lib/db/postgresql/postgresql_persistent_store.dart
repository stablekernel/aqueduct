part of aqueduct;

class PostgreSQLPersistentStore extends PersistentStore {
  static Logger logger = new Logger("aqueduct");
  static Map<MatcherOperator, String> symbolTable = {
    MatcherOperator.lessThan : "<",
    MatcherOperator.greaterThan : ">",
    MatcherOperator.notEqual : "!=",
    MatcherOperator.lessThanEqualTo : "<=",
    MatcherOperator.greaterThanEqualTo : ">=",
    MatcherOperator.equalTo : "="
  };

  Connection _databaseConnection;
  Function connectFunction;

  PostgreSQLPersistentStore(this.connectFunction) : super();
  PostgreSQLPersistentStore.fromConnectionInfo(String username, String password, String host, int port, String databaseName, {String timezone: "UTC"}) {
    var uri = "postgres://$username:$password@$host:$port/$databaseName";
    this.connectFunction = () async {
      logger.info("PostgreSQL connecting, $username@$host:$port/$databaseName.");
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
  Future<dynamic> execute(String sql) async {
    var dbConnection = await getDatabaseConnection();
    return await dbConnection.execute(sql);
  }

  @override
  Future close() async {
    await _databaseConnection?.close();
    _databaseConnection = null;
  }

  String _columnNameForProperty(PropertyDescription desc) {
    if (desc is RelationshipDescription) {
      return "${desc.name}_${desc.destinationEntity.primaryKey}";
    }
    return desc.name;
  }

  Future<dynamic> _executeQuery(String formatString, dynamic values, int timeoutInSeconds, {bool returnCount: false}) async {
    try {
      var dbConnection = await getDatabaseConnection();
      var results = null;

      var now = new DateTime.now().toUtc();
      if (!returnCount) {
        results = (await dbConnection.query(formatString, values).toList().timeout(new Duration(seconds: timeoutInSeconds)));
      } else {
        results = (await dbConnection.execute(formatString, values).timeout(new Duration(seconds: timeoutInSeconds)));
      }

      logger.fine(() => "Query (${(new DateTime.now().toUtc().difference(now).inMilliseconds)}ms) $formatString $values -> $results");

      return results;
    } on TimeoutException {
      throw new QueryException(503, "Could not connect to database.", -1);
    } on PostgresqlException catch (e, stackTrace) {
      logger.severe("SQL Failed $formatString $values");
      throw _interpretException(e, stackTrace);
    } on QueryException {
      logger.severe("Query Failed $formatString $values");
      rethrow;
    } catch (e, stackTrace) {
      logger.severe("Unknown Failure $formatString $values");
      throw new QueryException(500, e.toString(), -1, stackTrace: stackTrace);
    }
  }

  Future<List<MappingElement>> executeInsertQuery(PersistentStoreQuery q) async {
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("insert into ${q.entity.tableName} ");
    queryStringBuffer.write("(${q.values.map((m) => _columnNameForProperty(m.property)).join(",")}) ");
    queryStringBuffer.write("values (${q.values.map((m) => "@${_columnNameForProperty(m.property)}").join(",")}) ");

    if (q.resultKeys != null && q.resultKeys.length > 0) {
      queryStringBuffer.write("returning ${q.resultKeys.map((m) => _columnNameForProperty(m.property)).join(",")} ");
    }
    var valueMap = new Map.fromIterable(q.values,
        key: (MappingElement m) => _columnNameForProperty(m.property),
        value: (MappingElement m) => m.value);

    var results = await _executeQuery(queryStringBuffer.toString(), valueMap, q.timeoutInSeconds);

    return _mappingElementsFromResults(results, q.resultKeys).first;
  }

  Future<List<List<MappingElement>>> executeFetchQuery(PersistentStoreQuery q) async {
    var queryStringBuffer = new StringBuffer("select ");

    var predicateValueMap = {};
    var mapElementToString = (MappingElement e) => "${e.property.entity.tableName}.${_columnNameForProperty(e.property)}";
    var selectColumns =  q.resultKeys
        .map((mapElement) {
          if (mapElement is JoinMappingElement) {
            return mapElement.resultKeys.map(mapElementToString).join(",");
          } else {
            return mapElementToString(mapElement);
          }
        }).join(",");

    queryStringBuffer.write("$selectColumns from ${q.entity.tableName} ");

    q.resultKeys.where((mapElement) => mapElement is JoinMappingElement)
        .forEach((JoinMappingElement joinElement) {
          queryStringBuffer.write("${_joinStringForJoin(joinElement)} ");
          if (joinElement.predicate != null) {
            predicateValueMap.addAll(joinElement.predicate.parameters);
          }
        });

    var allPredicates = Predicate.andPredicates([q.predicate, _pagePredicateForQuery(q)].where((p) => p != null).toList());
    if (allPredicates != null) {
      queryStringBuffer.write("where ${allPredicates.format} ");
      predicateValueMap.addAll(allPredicates.parameters);
    }

    var orderingString = _orderByStringForQuery(q);
    if (orderingString != null) {
      queryStringBuffer.write("$orderingString ");
    }

    if (q.fetchLimit != 0) {
      queryStringBuffer.write("limit ${q.fetchLimit} ");
    }

    if (q.offset != 0) {
      queryStringBuffer.write("offset ${q.offset} ");
    }

    var results = await _executeQuery(queryStringBuffer.toString(), predicateValueMap, q.timeoutInSeconds);

    return _mappingElementsFromResults(results, q.resultKeys);
  }

  Future<int> executeDeleteQuery(PersistentStoreQuery q) async {
    if (q.predicate == null && !q.confirmQueryModifiesAllInstancesOnDeleteOrUpdate) {
      throw new HTTPResponseException(500, "Query would impact all records. This could be a destructive error. Set confirmQueryModifiesAllInstancesOnDeleteOrUpdate on the Query to execute anyway.");
    }

    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("delete from ${q.entity.tableName} ");

    var valueMap = null;
    if (q.predicate != null) {
      queryStringBuffer.write("where ${q.predicate.format} ");
      valueMap = q.predicate.parameters;
    }

    var results = await _executeQuery(queryStringBuffer.toString(), valueMap, q.timeoutInSeconds, returnCount: true);

    return results;
  }

  Future<List<List<MappingElement>>> executeUpdateQuery(PersistentStoreQuery q) async {
    if (q.predicate == null && !q.confirmQueryModifiesAllInstancesOnDeleteOrUpdate) {
      throw new HTTPResponseException(500, "Query would impact all records. This could be a destructive error. Set confirmQueryModifiesAllInstancesOnDeleteOrUpdate on the Query to execute anyway.");
    }

    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("update ${q.entity.tableName} ");
    queryStringBuffer.write("set ${q.values.map((m) => _columnNameForProperty(m.property)).map((keyName) => "$keyName=@u_$keyName").join(",")} ");

    var predicateValueMap = {};
    if (q.predicate != null) {
      queryStringBuffer.write("where ${q.predicate.format} ");
      predicateValueMap = q.predicate.parameters;
    }

    if (q.resultKeys != null && q.resultKeys.length > 0) {
      queryStringBuffer.write("returning ${q.resultKeys.map((m) => _columnNameForProperty(m.property)).join(",")} ");
    }

    var updateValueMap = new Map.fromIterable(q.values,
        key: (MappingElement elem) => "u_${_columnNameForProperty(elem.property)}",
        value: (MappingElement elem) => elem.value);
    updateValueMap.addAll(predicateValueMap);

    var results = await _executeQuery(queryStringBuffer.toString(), updateValueMap, q.timeoutInSeconds);

    return _mappingElementsFromResults(results, q.resultKeys);
  }

  @override
  Predicate comparisonPredicate(PropertyDescription desc, MatcherOperator operator, dynamic value) {
    var prefix = desc.entity.tableName;
    var columnName = _columnNameForProperty(desc);
    var formatSpecificationName = "$prefix${columnName}";
    return new Predicate("$prefix.${columnName} ${symbolTable[operator]} @$formatSpecificationName",  {formatSpecificationName : value});
  }

  @override
  Predicate containsPredicate(PropertyDescription desc, Iterable<dynamic> values) {
    var tokenList = [];
    var pairedMap = {};
    var prefix = desc.entity.tableName;
    var propertyName = _columnNameForProperty(desc);

    var counter = 0;
    values.forEach((value) {
      var token = "wme$prefix${propertyName}_$counter";
      tokenList.add("@$token");
      pairedMap[token] = value;

      counter ++;
    });

    return new Predicate("$prefix.$propertyName in (${tokenList.join(",")})", pairedMap);
  }

  @override
  Predicate nullPredicate(PropertyDescription desc, bool isNull) {
    var prefix = desc.entity.tableName;
    var propertyName = _columnNameForProperty(desc);
    return new Predicate("$prefix.$propertyName ${isNull ? "isnull" : "notnull"}", {});
  }

  @override
  Predicate rangePredicate(PropertyDescription desc, dynamic lhsValue, dynamic rhsValue, bool insideRange) {
    var prefix = desc.entity.tableName;
    var propertyName = _columnNameForProperty(desc);
    var lhsFormatSpecificationName = "$prefix${propertyName}_lhs";
    var rhsRormatSpecificationName = "$prefix${propertyName}_rhs";
    return new Predicate("$prefix.$propertyName ${insideRange ? "between" : "not between"} @$lhsFormatSpecificationName and @$rhsRormatSpecificationName",
        {lhsFormatSpecificationName: lhsValue, rhsRormatSpecificationName : rhsValue});
  }

  @override
  Predicate stringPredicate(PropertyDescription desc, StringMatcherOperator operator, dynamic value) {
    var prefix = desc.entity.tableName;
    var propertyName = _columnNameForProperty(desc);
    var formatSpecificationName = "$prefix${propertyName}";
    var matchValue = value;
    switch(operator) {
      case StringMatcherOperator.beginsWith: matchValue = "$matchValue%"; break;
      case StringMatcherOperator.endsWith: matchValue = "%$matchValue"; break;
      case StringMatcherOperator.contains: matchValue = "%$matchValue%"; break;
    }

    return new Predicate("$prefix.$propertyName like @$formatSpecificationName", {formatSpecificationName : matchValue});
  }

  List<List<MappingElement>> _mappingElementsFromResults(List<Row> rows, List<MappingElement> columnDefinitions) {
    return rows.map((row) {
      var columnDefinitionIterator = columnDefinitions.iterator;
      var rowIterator = row.toList().iterator;
      var resultColumns = [];

      while (columnDefinitionIterator.moveNext()) {
        var element = columnDefinitionIterator.current;

        if (element is JoinMappingElement) {
          var innerColumnIterator = element.resultKeys.iterator;
          var innerResultColumns = [];
          while (innerColumnIterator.moveNext()) {
            rowIterator.moveNext();
            innerResultColumns.add(new MappingElement.fromElement(innerColumnIterator.current, rowIterator.current));
          }
          resultColumns.add(new JoinMappingElement.fromElement(element, innerResultColumns));
        } else {
          rowIterator.moveNext();
          resultColumns.add(new MappingElement.fromElement(element, rowIterator.current));
        }
      }

      return resultColumns;
    }).toList();
  }

  QueryException _interpretException(PostgresqlException exception, StackTrace stackTrace) {
    ServerMessage msg = exception.serverMessage;
    if (msg == null) {
      return new QueryException(500, exception.message, 0, stackTrace: stackTrace);
    }

    var totalMessage = "${exception.message}${msg.detail != null ? ": ${msg.detail}" : ""}";
    switch (msg.code) {
      case "42703":
        return new QueryException(400, totalMessage, 42703, stackTrace: stackTrace);
      case "23505":
        return new QueryException(409, totalMessage, 23505, stackTrace: stackTrace);
      case "23502":
        return new QueryException(400, totalMessage, 23502, stackTrace: stackTrace);
      case "23503":
        return new QueryException(400, totalMessage, 23503, stackTrace: stackTrace);
    }

    return new QueryException(500, exception.message, 0, stackTrace: stackTrace);
  }

  String _orderByStringForQuery(PersistentStoreQuery q) {
    List<SortDescriptor> sortDescs = q.sortDescriptors ?? [];

    if (q.pageDescriptor != null) {
      var order = (q.pageDescriptor.direction == PageDirection.after
          ? SortDescriptorOrder.ascending
          : SortDescriptorOrder.descending);

      sortDescs.insert(0, new SortDescriptor(q.pageDescriptor.referenceKey, order));
    }

    if (sortDescs.length == 0) {
      return null;
    }

    var transformFunc = (SortDescriptor sd) {
      var property = q.entity.properties[sd.key];
      var columnName = "${property.entity.tableName}.${_columnNameForProperty(property)}";
      return "$columnName ${(sd.order == SortDescriptorOrder.ascending ? "asc" : "desc")}";
    };
    var joinedSortDescriptors = sortDescs.map(transformFunc).join(",");

    return "order by $joinedSortDescriptors";
  }

  Predicate _pagePredicateForQuery(PersistentStoreQuery query) {
    if(query.pageDescriptor?.referenceValue == null) {
      return null;
    }

    var operator = (query.pageDescriptor.direction == PageDirection.after ? ">" : "<");
    return new Predicate("${query.pageDescriptor.referenceKey} ${operator} @inq_page_value",
        {"inq_page_value": query.pageDescriptor.referenceValue});
  }

  String _joinStringForJoin(JoinMappingElement ji) {
    var parentEntity = ji.property.entity;
    var childEntity = ji.joinProperty.entity;
    var predicate = new Predicate("${parentEntity.tableName}.${_columnNameForProperty(parentEntity.properties[parentEntity.primaryKey])}=${childEntity.tableName}.${_columnNameForProperty(ji.joinProperty)}", {});
    if (ji.predicate != null) {
      predicate = Predicate.andPredicates([predicate, ji.predicate]);
    }

    return "${_stringForJoinType(ji.type)} join ${ji.joinProperty.entity.tableName} on (${predicate.format})";
  }

  String _stringForJoinType(JoinType t) {
    switch (t) {
      case JoinType.leftOuter: return "left outer";
    }
    return null;
  }
}

class PostgreSQLPersistentStoreException implements Exception {
  PostgreSQLPersistentStoreException(this.message);
  String message;

  String toString() {
    return "PostgreSQLPersistentStoreException: $message";
  }
}