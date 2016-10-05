part of aqueduct;

class PostgreSQLPersistentStore extends PersistentStore with PostgreSQLSchemaGenerator {
  static Logger logger = new Logger("aqueduct");
  static Map<MatcherOperator, String> symbolTable = {
    MatcherOperator.lessThan : "<",
    MatcherOperator.greaterThan : ">",
    MatcherOperator.notEqual : "!=",
    MatcherOperator.lessThanEqualTo : "<=",
    MatcherOperator.greaterThanEqualTo : ">=",
    MatcherOperator.equalTo : "="
  };

  PostgreSQLConnection _databaseConnection;
  Function connectFunction;
  bool _isConnecting = false;
  List<Completer<PostgreSQLConnection>> _pendingConnectionCompleters = [];

  PostgreSQLPersistentStore(this.connectFunction) : super();
  PostgreSQLPersistentStore.fromConnectionInfo(String username, String password, String host, int port, String databaseName, {String timezone: "UTC"}) {
    this.connectFunction = () async {
      logger.info("PostgreSQL connecting, $username@$host:$port/$databaseName.");
      var connection = new PostgreSQLConnection(host, port, databaseName, username: username, password: password, timeZone: timezone);
      await connection.open();
      return connection;
    };
  }

  Future<PostgreSQLConnection> getDatabaseConnection() async {
    if (_databaseConnection == null || _databaseConnection.isClosed) {
      if (connectFunction == null) {
        throw new QueryException(QueryExceptionEvent.internalFailure, message: "Could not connect to database, no connect function.");
      }

      if (_isConnecting) {
        var completer = new Completer<PostgreSQLConnection>();
        _pendingConnectionCompleters.add(completer);
        return completer.future;
      }

      _isConnecting = true;
      try {
        _databaseConnection = await connectFunction();
        _isConnecting = false;
        _informWaiters((completer) {
          completer.complete(_databaseConnection);
        });
      } catch (e) {
        _isConnecting = false;

        var exception = new QueryException(QueryExceptionEvent.connectionFailure, underlyingException: e);
        _informWaiters((completer) {
          completer.completeError(exception);
        });

        throw exception;
      }
    }

    return _databaseConnection;
  }

  @override
  Future<dynamic> execute(String sql) async {
    var now = new DateTime.now().toUtc();
    var dbConnection = await getDatabaseConnection();
    var results = await dbConnection.query(sql);
    var rows = await results.toList();

    var mappedRows = rows.map((row) => row.toList()).toList();
    logger.fine(() => "Query:execute (${(new DateTime.now().toUtc().difference(now).inMilliseconds)}ms) $sql -> $mappedRows");
    return mappedRows;
  }

  @override
  Future close() async {
    await _databaseConnection?.close();
    _databaseConnection = null;
  }

  void _informWaiters(void f(Completer c)) {
    if (!_pendingConnectionCompleters.isEmpty) {
      List<Completer<PostgreSQLConnection>> copiedCompleters = new List.from(_pendingConnectionCompleters);
      _pendingConnectionCompleters = [];
      copiedCompleters.forEach((completer) {
        scheduleMicrotask(() {
          f(completer);
        });
      });
    }
  }

  String _columnNameForProperty(PropertyDescription desc) {
    if (desc is RelationshipDescription) {
      return "${desc.name}_${desc.destinationEntity.primaryKey}";
    }
    return desc.name;
  }

  static Map<PropertyType, PostgreSQLDataType> _typeMap = {
    PropertyType.integer : PostgreSQLDataType.integer,
    PropertyType.bigInteger : PostgreSQLDataType.bigInteger,
    PropertyType.string : PostgreSQLDataType.text,
    PropertyType.datetime : PostgreSQLDataType.timestampWithoutTimezone,
    PropertyType.boolean : PostgreSQLDataType.boolean,
    PropertyType.doublePrecision : PostgreSQLDataType.double
  };

  String _typedColumnName(String name, PropertyDescription desc) {
    var type = PostgreSQLFormat.dataTypeStringForDataType(_typeMap[desc.type]);
    if (type == null) {
      return name;
    }
    return "$name:$type";
  }

  Future<dynamic> _executeQuery(String formatString, Map<String, dynamic> values, int timeoutInSeconds, {bool returnCount: false}) async {
    var now = new DateTime.now().toUtc();
    try {
      var dbConnection = await getDatabaseConnection();
      var results = null;

      if (!returnCount) {
        results = await dbConnection.query(formatString, substitutionValues: values).timeout(new Duration(seconds: timeoutInSeconds));
      } else {
        results = await dbConnection.execute(formatString, substitutionValues: values).timeout(new Duration(seconds: timeoutInSeconds));
      }

      logger.fine(() => "Query (${(new DateTime.now().toUtc().difference(now).inMilliseconds)}ms) $formatString $values -> $results");

      return results;
    } on TimeoutException catch (e) {
      throw new QueryException(QueryExceptionEvent.connectionFailure, underlyingException: e);
    } on PostgreSQLException catch (e) {
      logger.fine(() => "Query (${(new DateTime.now().toUtc().difference(now).inMilliseconds)}ms) $formatString $values");
      throw _interpretException(e);
    }
  }

  Future<List<MappingElement>> executeInsertQuery(PersistentStoreQuery q) async {
    var columnsBeingInserted = q.values
        .map((m) => _columnNameForProperty(m.property))
        .join(",");
    var valueKeysToBeInserted = q.values
        .map((m) => "@${_typedColumnName(_columnNameForProperty(m.property), m.property)}")
        .join(",");
    var columnsToBeReturned = q.resultKeys
        .map((m) => _columnNameForProperty(m.property))
        .join(",");
    var valueMap = new Map.fromIterable(q.values,
        key: (MappingElement m) => _columnNameForProperty(m.property),
        value: (MappingElement m) => m.value);


    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("INSERT INTO ${q.rootEntity.tableName} ($columnsBeingInserted) ");
    queryStringBuffer.write("VALUES (${valueKeysToBeInserted}) ");

    if (q.resultKeys != null && q.resultKeys.length > 0) {
      queryStringBuffer.write("RETURNING $columnsToBeReturned ");
    }
    var results = await _executeQuery(queryStringBuffer.toString(), valueMap, q.timeoutInSeconds);

    return _mappingElementsFromResults(results as List<List<dynamic>>, q.resultKeys).first;
  }

  Future<List<List<MappingElement>>> executeFetchQuery(PersistentStoreQuery q) async {
    var predicateValueMap = <String, dynamic>{};
    var mapElementToStringTransform = (MappingElement e) => "${e.property.entity.tableName}.${_columnNameForProperty(e.property)}";
    var joinElements = q.resultKeys.where((mapElement) => mapElement is JoinMappingElement);
    var allPredicates = Predicate.andPredicates([q.predicate, _pagePredicateForQuery(q)].where((p) => p != null).toList());
    var orderingString = _orderByStringForQuery(q);
    var columnsToFetch = q.resultKeys.map((mapElement) {
      if (mapElement is JoinMappingElement) {
        return mapElement.resultKeys.map(mapElementToStringTransform).join(",");
      } else {
        return mapElementToStringTransform(mapElement);
      }
    }).join(",");

    var queryStringBuffer = new StringBuffer("SELECT $columnsToFetch FROM ${q.rootEntity.tableName} ");
    joinElements
        .forEach((MappingElement je) {
          JoinMappingElement joinElement = je;
          queryStringBuffer.write("${_joinStringForJoin(joinElement)} ");

          if (joinElement.predicate != null) {
            predicateValueMap.addAll(joinElement.predicate.parameters);
          }
        });

    if (allPredicates != null) {
      queryStringBuffer.write("WHERE ${allPredicates.format} ");
      predicateValueMap.addAll(allPredicates.parameters);
    }

    if (orderingString != null) {
      queryStringBuffer.write("$orderingString ");
    }

    if (q.fetchLimit != 0) {
      queryStringBuffer.write("LIMIT ${q.fetchLimit} ");
    }

    if (q.offset != 0) {
      queryStringBuffer.write("OFFSET ${q.offset} ");
    }

    var results = await _executeQuery(queryStringBuffer.toString(), predicateValueMap, q.timeoutInSeconds);

    return _mappingElementsFromResults(results as List<List<dynamic>>, q.resultKeys);
  }

  Future<int> executeDeleteQuery(PersistentStoreQuery q) async {
    if (q.predicate == null && !q.confirmQueryModifiesAllInstancesOnDeleteOrUpdate) {
      throw new QueryException(QueryExceptionEvent.internalFailure, message: "Query would impact all records. This could be a destructive error. Set confirmQueryModifiesAllInstancesOnDeleteOrUpdate on the Query to execute anyway.");
    }

    Map<String, dynamic> valueMap = null;
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("DELETE FROM ${q.rootEntity.tableName} ");

    if (q.predicate != null) {
      queryStringBuffer.write("where ${q.predicate.format} ");
      valueMap = q.predicate.parameters;
    }

    var results = await _executeQuery(queryStringBuffer.toString(), valueMap, q.timeoutInSeconds, returnCount: true);

    return results;
  }

  Future<List<List<MappingElement>>> executeUpdateQuery(PersistentStoreQuery q) async {
    if (q.predicate == null && !q.confirmQueryModifiesAllInstancesOnDeleteOrUpdate) {
      throw new QueryException(QueryExceptionEvent.internalFailure, message: "Query would impact all records. This could be a destructive error. Set confirmQueryModifiesAllInstancesOnDeleteOrUpdate on the Query to execute anyway.");
    }

    var resultColumnString = q.resultKeys.map((m) => _columnNameForProperty(m.property)).join(",");
    var updateValueMap = new Map.fromIterable(q.values,
        key: (MappingElement elem) => "u_${_columnNameForProperty(elem.property)}",
        value: (MappingElement elem) => elem.value);
    var setPairString = q.values.map((m) {
      var name = _columnNameForProperty(m.property);
      var typedName = _typedColumnName(name, m.property);
      return "$name=@u_$typedName";
    }).join(",");

    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("UPDATE ${q.rootEntity.tableName} SET $setPairString ");

    if (q.predicate != null) {
      queryStringBuffer.write("where ${q.predicate.format} ");
      updateValueMap.addAll(q.predicate.parameters);
    }
    if (q.resultKeys != null && q.resultKeys.length > 0) {
      queryStringBuffer.write("RETURNING $resultColumnString ");
    }

    var results = await _executeQuery(queryStringBuffer.toString(), updateValueMap, q.timeoutInSeconds);

    return _mappingElementsFromResults(results as List<List<dynamic>>, q.resultKeys);
  }

  @override
  Predicate comparisonPredicate(PropertyDescription desc, MatcherOperator operator, dynamic value) {
    var tableName = desc.entity.tableName;
    var columnName = _columnNameForProperty(desc);
    var typedColumnName = _typedColumnName(columnName, desc);

    return new Predicate("$tableName.$columnName ${symbolTable[operator]} @${tableName}_$typedColumnName", {
      "${tableName}_$columnName" : value
    });
  }

  @override
  Predicate containsPredicate(PropertyDescription desc, Iterable<dynamic> values) {
    var tableName = desc.entity.tableName;
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "ctns${tableName}_${counter}";
      var columnName = _columnNameForProperty(desc);
      var typedName = _typedColumnName(columnName, desc);
      tokenList.add("@${prefix}_$typedName");
      pairedMap["${prefix}_$columnName"] = value;

      counter ++;
    });

    return new Predicate("$tableName.${_columnNameForProperty(desc)} IN (${tokenList.join(",")})", pairedMap);
  }

  @override
  Predicate nullPredicate(PropertyDescription desc, bool isNull) {
    var tableName = desc.entity.tableName;
    var propertyName = _columnNameForProperty(desc);
    return new Predicate("$tableName.$propertyName ${isNull ? "isnull" : "notnull"}", {});
  }

  @override
  Predicate rangePredicate(PropertyDescription desc, dynamic lhsValue, dynamic rhsValue, bool insideRange) {
    var prefix = desc.entity.tableName;
    var propertyName = _columnNameForProperty(desc);
    var typedName = _typedColumnName(propertyName, desc);
    var lhsFormatSpecificationName = "${prefix}_lhs_$typedName";
    var rhsFormatSpecificationName = "${prefix}_rhs_$typedName";
    var lhsKeyName = "${prefix}_lhs_$propertyName";
    var rhsKeyName = "${prefix}_rhs_$propertyName";
    var operation = insideRange ? "between" : "not between";

    return new Predicate("$prefix.$propertyName $operation @$lhsFormatSpecificationName AND @$rhsFormatSpecificationName", {
      lhsKeyName: lhsValue, rhsKeyName : rhsValue
    });
  }

  @override
  Predicate stringPredicate(PropertyDescription desc, StringMatcherOperator operator, dynamic value) {
    var tableName = desc.entity.tableName;
    var propertyName = _columnNameForProperty(desc);
    var formatSpecificationName = "${tableName}_${_typedColumnName(propertyName, desc)}";
    var keyName = "${tableName}_$propertyName";
    var matchValue = value;
    switch(operator) {
      case StringMatcherOperator.beginsWith: matchValue = "$value%"; break;
      case StringMatcherOperator.endsWith: matchValue = "%$value"; break;
      case StringMatcherOperator.contains: matchValue = "%$value%"; break;
    }

    return new Predicate("$tableName.$propertyName like @$formatSpecificationName", {keyName : matchValue});
  }

  SchemaTable get _versionTable {
    return new SchemaTable.empty()
      ..name = "_aqueduct_version_pgsql"
      ..columns = [
        (new SchemaColumn.empty()..name = "versionNumber"..type = SchemaColumn.typeStringForType(PropertyType.integer)),
        (new SchemaColumn.empty()..name = "dateOfUpgrade"..type = SchemaColumn.typeStringForType(PropertyType.datetime)),
      ];
  }

  Future createVersionTableIfNecessary() async {
    var commands = createTable(_versionTable);
    for (var cmd in commands) {
      await execute(cmd);
    }
  }

  Future<int> get schemaVersion async {
    var values = await execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql ORDER BY dateOfUpgrade ASC") as List<List<dynamic>>;

    if (values.length == 0) {
      return 0;
    }

    return values.last.first;
  }

  List<List<MappingElement>> _mappingElementsFromResults(List<List<dynamic>> rows, List<MappingElement> columnDefinitions) {
    return rows.map((row) {
      var columnDefinitionIterator = columnDefinitions.iterator;
      var rowValueIterator = row.toList().iterator;
      var resultColumns = [];

      while (columnDefinitionIterator.moveNext()) {
        var element = columnDefinitionIterator.current;

        if (element is JoinMappingElement) {
          var innerColumnIterator = element.resultKeys.iterator;
          var innerResultColumns = <MappingElement>[];
          while (innerColumnIterator.moveNext()) {
            rowValueIterator.moveNext();
            innerResultColumns.add(new MappingElement.fromElement(innerColumnIterator.current, rowValueIterator.current));
          }
          resultColumns.add(new JoinMappingElement.fromElement(element, innerResultColumns));
        } else {
          rowValueIterator.moveNext();
          resultColumns.add(new MappingElement.fromElement(element, rowValueIterator.current));
        }
      }

      return resultColumns;
    }).toList();
  }

  QueryException _interpretException(PostgreSQLException exception) {
    switch (exception.code) {
      case "42703":
        return new QueryException(QueryExceptionEvent.requestFailure, underlyingException: exception);
      case "23505":
        return new QueryException(QueryExceptionEvent.conflict, underlyingException: exception);
      case "23502":
        return new QueryException(QueryExceptionEvent.requestFailure, underlyingException: exception);
      case "23503":
        return new QueryException(QueryExceptionEvent.requestFailure, underlyingException: exception);
    }

    return new QueryException(QueryExceptionEvent.internalFailure, underlyingException: exception);
  }

  String _orderByStringForQuery(PersistentStoreQuery q) {
    List<SortDescriptor> sortDescs = q.sortDescriptors ?? [];
    if (q.pageDescriptor != null) {
      sortDescs.insert(0, new SortDescriptor(q.pageDescriptor.propertyName, q.pageDescriptor.order));
    }

    if (sortDescs.length == 0) {
      return null;
    }

    var joinedSortDescriptors = sortDescs.map((SortDescriptor sd) {
      var property = q.rootEntity.properties[sd.key];
      var columnName = "${property.entity.tableName}.${_columnNameForProperty(property)}";
      var order = (sd.order == SortOrder.ascending ? "ASC" : "DESC");
      return "$columnName $order";
    }).join(",");

    return "ORDER BY $joinedSortDescriptors";
  }

  Predicate _pagePredicateForQuery(PersistentStoreQuery query) {
    if(query.pageDescriptor?.boundingValue == null) {
      return null;
    }

    var operator = (query.pageDescriptor.order == SortOrder.ascending ? ">" : "<");
    var keyName = "aq_page_value";
    var typedKeyName = _typedColumnName(keyName, query.rootEntity.properties[query.pageDescriptor.propertyName]);
    return new Predicate("${query.pageDescriptor.propertyName} ${operator} @$typedKeyName", {
      "$keyName": query.pageDescriptor.boundingValue
    });
  }

  String _joinStringForJoin(JoinMappingElement ji) {
    var parentEntity = ji.property.entity;
    var childEntity = ji.joinProperty.entity;
    var predicate = new Predicate("${parentEntity.tableName}.${_columnNameForProperty(parentEntity.properties[parentEntity.primaryKey])}=${childEntity.tableName}.${_columnNameForProperty(ji.joinProperty)}", {});
    if (ji.predicate != null) {
      predicate = Predicate.andPredicates([predicate, ji.predicate]);
    }

    return "${_stringForJoinType(ji.type)} JOIN ${ji.joinProperty.entity.tableName} ON (${predicate.format})";
  }

  String _stringForJoinType(JoinType t) {
    switch (t) {
      case JoinType.leftOuter: return "LEFT OUTER";
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