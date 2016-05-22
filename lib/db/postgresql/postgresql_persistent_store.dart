part of aqueduct;

class PostgreSQLPersistentStore extends PersistentStore {
  static Logger logger = new Logger("aqueduct");

  Connection _databaseConnection;
  Function connectFunction;

  PostgreSQLPersistentStore(this.connectFunction) : super();
  PostgreSQLPersistentStore.fromConnectionInfo(String username, String password, String host, int port, String databaseName, {String timezone: "UTC"}) {
    var uri = "postgres://$username:$password@$host:$port/$databaseName";
    this.connectFunction = () async {
      logger.info("PostgresqlModelAdapter connecting, $username@$host:$port/$databaseName.");
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

  @override
  String foreignKeyForRelationshipDescription(RelationshipDescription desc) {
    return "${desc.name}_${desc.destinationEntity.primaryKey}";
  }

  Future<List<Row>> _executeQuery(String formatString, dynamic values, int timeoutInSeconds, {bool returnCount: false}) async {
    try {
      var dbConnection = await getDatabaseConnection();
      print("$formatString $values");
      if (!returnCount) {
        return (await dbConnection.query(formatString, values).toList().timeout(new Duration(seconds: timeoutInSeconds)));
      } else {
        return (await dbConnection.execute(formatString, values).timeout(new Duration(seconds: timeoutInSeconds)));
      }
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
    queryStringBuffer.write("(${q.values.map((m) => m.property.columnName).join(",")}) ");
    queryStringBuffer.write("values (${q.values.map((m) => "@${m.property.columnName}").join(",")}) ");

    if (q.resultKeys != null && q.resultKeys.length > 0) {
      queryStringBuffer.write("returning ${q.resultKeys.map((m) => m.property.columnName).join(",")} ");
    }
    var valueMap = new Map.fromIterable(q.values,
        key: (MappingElement m) => m.property.columnName,
        value: (MappingElement m) => m.value);

    var results = await _executeQuery(queryStringBuffer.toString(), valueMap, q.timeoutInSeconds);
    return _mappingElementsFromResults(results, q.resultKeys).first;
  }

  Future<List<List<MappingElement>>> executeFetchQuery(PersistentStoreQuery q) async {
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("select ${q.resultKeys.map((m) => m.property.columnName).join(",")} from ${q.entity.tableName} ");

    var valueMap = null;
    var allPredicates = Predicate.andPredicates([q.predicate, _pagePredicateForQuery(q)].where((p) => p != null).toList());
    if (allPredicates != null) {
      queryStringBuffer.write("where ${allPredicates.format} ");
      valueMap = allPredicates.parameters;
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

    var results = await _executeQuery(queryStringBuffer.toString(), valueMap, q.timeoutInSeconds);

    return _mappingElementsFromResults(results, q.resultKeys);
  }

  Future<int> executeDeleteQuery(PersistentStoreQuery q) async {
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
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("update ${q.entity.tableName} ");
    queryStringBuffer.write("set ${q.values.map((m) => m.property.columnName).map((keyName) => "$keyName=@u_$keyName").join(",")} ");

    var predicateValueMap = {};
    if (q.predicate != null) {
      queryStringBuffer.write("where ${q.predicate.format} ");
      predicateValueMap = q.predicate.parameters;
    }

    if (q.resultKeys != null && q.resultKeys.length > 0) {
      queryStringBuffer.write("returning ${q.resultKeys.map((m) => m.property.columnName).join(",")} ");
    }

    var updateValueMap = new Map.fromIterable(q.values,
        key: (MappingElement elem) => "u_${elem.property.columnName}",
        value: (MappingElement elem) => elem.value);
    updateValueMap.addAll(predicateValueMap);

    var results = await _executeQuery(queryStringBuffer.toString(), updateValueMap, q.timeoutInSeconds);

    return _mappingElementsFromResults(results, q.resultKeys);
  }

  Future<int> executeCountQuery(PersistentStoreQuery q) async {

  }

  List<List<MappingElement>> _mappingElementsFromResults(List<Row> rows, List<MappingElement> columns) {
    return rows.map((row) {
      var iterator = columns.iterator;
      return row.toList().map((columnValue) {
        iterator.moveNext();
        return new MappingElement()
          ..property = iterator.current.property
          ..value = columnValue;
      }).toList();
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

    var transformFunc = (SortDescriptor sd) => "${q.entity.properties[sd.key].name} ${(sd.order == SortDescriptorOrder.ascending ? "asc" : "desc")}";
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
}

class PostgreSQLPersistentStoreException implements Exception {
  PostgreSQLPersistentStoreException(this.message);
  String message;

  String toString() {
    return "PostgreSQLPersistentStoreException: $message";
  }
}
/*
class PostgresModelAdapter extends QueryAdapter {
  static Logger logger = new Logger("aqueduct");

  PostgresqlSchema schema;
  Connection _databaseConnection;
  Function connectFunction;

  PostgresModelAdapter(this.schema, this.connectFunction);

  PostgresModelAdapter.fromConnectionInfo(
      this.schema, String username, String password, String host, int port, String databaseName,
      {String timezone: "UTC"}) {
    var uri = "postgres://$username:$password@$host:$port/$databaseName";
    this.connectFunction = () async {
      logger.info("PostgresqlModelAdapter connecting, $username@$host:$port/$databaseName.");
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
  Future<dynamic> execute(Query query) async {
    _PostgresqlQuery pgsqlQuery = new _PostgresqlQuery(schema, query);
    pgsqlQuery.logger = logger;

    var statement = pgsqlQuery.statement;
    statement.compile();

    var formatString = statement.formatString;
    var formatParameters = statement.formatParameters;

    try {
      var conn = await getDatabaseConnection();
      if (pgsqlQuery.resultColumnNames != null && pgsqlQuery.resultColumnNames.length > 0) {
        var results = await conn.query(formatString, formatParameters).toList();
        logger?.fine("Querying $formatString");

        return mapRowsAccordingToQuery(results, pgsqlQuery);
      } else {
        var result = await conn.execute(formatString, formatParameters);
        logger?.fine("Executing $formatString");

        return result;
      }
    } on TimeoutException {
      throw new QueryException(503, "Could not connect to database.", -1);
    } on PostgresqlException catch (e, stackTrace) {
      logger.severe("SQL Failed $formatString $formatParameters");
      throw interpretException(e, stackTrace);
    } on QueryException {
      logger.severe("Query Failed $formatString $formatParameters");
      rethrow;
    } catch (e, stackTrace) {
      logger.severe("Unknown Failure $formatString $formatParameters");
      throw new QueryException(500, e.toString(), -1, stackTrace: stackTrace);
    }
  }

  Exception interpretException(PostgresqlException exception, StackTrace stackTrace) {
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

  List<Model> mapRowsAccordingToQuery(List<Row> rows, _PostgresqlQuery query) {
    var representedEntities = new Set.from(query.resultMappingElements.map((e) => e.entity));
    var objectCache = new Map.fromIterable(representedEntities, key: (e) => e, value: (e) => {});
    Map<ModelEntity, _RowRange> entityRowRangeMap = rangeMapForQuery(query);
    List<Model> instantiatedObjects = [];
    Map<ModelEntity, ClassMirror> entityToModelClassMirrorMapping = new Map.fromIterable(representedEntities, key: (k) => k, value: (entity) {
      return reflectClass(query.resultMappingElements.firstWhere((e) => e.entity == entity).modelType);
    });

    rows.forEach((row) {
      var rowItems = row.toList();
      entityRowRangeMap.keys.forEach((entity) {
        var range = entityRowRangeMap[entity];
        var entityCache = objectCache[entity];

        var objectValues = rowItems.sublist(range.startIndex, range.endIndex + 1);
        var pkValue = objectValues[range.primaryKeyInnerIndex];
        if (pkValue == null) {
          return;
        }

        var existingObject = entityCache[pkValue];
        if (existingObject == null) {
          var newObject = instantiateObject(entityToModelClassMirrorMapping[entity], range, objectValues);
          entityCache[pkValue] = newObject;
          instantiatedObjects.add(newObject);
        }
      });
    });


    // Sew up relationships, replace foreign keys with model objects.
    instantiatedObjects.forEach((obj) {
      for (var key in obj.dynamicBacking.keys) {
        var value = obj.dynamicBacking[key];

        if (value is _DelayedInstanceForeignKey) {
          var entityCache = objectCache[value.entity];
          if (entityCache == null) {
            entityCache = {};
            objectCache[value.entity] = entityCache;
          }

          var cacheObject = entityCache[value.value];
          bool relatedObjectWasInResultSet = true;
          if (cacheObject == null) {
            relatedObjectWasInResultSet = false;
            cacheObject = reflectClass(value.type).newInstance(new Symbol(""), []).reflectee;
            cacheObject.dynamicBacking[value.entity.primaryKey] = value.value;
          }

          obj.dynamicBacking[key] = cacheObject;
          if(relatedObjectWasInResultSet) {
            // Set opposite side of relationship and prevent cycles
            var belongToRelationship = obj.entity.relationshipAttributeForProperty(key);
            var inverseKey = belongToRelationship.inverseKey;
            var ownerRelationship = cacheObject.entity.relationshipAttributeForProperty(inverseKey);

            if (ownerRelationship.type == RelationshipType.hasMany) {
              var list = cacheObject.dynamicBacking[inverseKey];
              if (list == null) {
                cacheObject.dynamicBacking[inverseKey] = [obj];
              } else {
                cacheObject.dynamicBacking[inverseKey].add(obj);
              }
            } else {
              cacheObject.dynamicBacking[inverseKey] = obj;
            }

            var replacementObject = reflectClass(value.type).newInstance(new Symbol(""), []).reflectee;
            replacementObject[value.entity.primaryKey] = cacheObject.dynamicBacking[value.entity.primaryKey];
            obj.dynamicBacking[key] = replacementObject;
          }
        }
      }
    });

    // Set any to-many relationships we wanted to fetch that yielded no results to the empty list,
    // to-one relationships will already be null.
    expectedRelationshipsForQuery(query.query).forEach((modelType, propertyName) {
      instantiatedObjects.where((o) => o.runtimeType == modelType)?.forEach((m) {
        if(m.entity.relationshipAttributeForProperty(propertyName).type == RelationshipType.hasMany) {
          if (m.dynamicBacking[propertyName] == null) {
            m.dynamicBacking[propertyName] = [];
          }
        }
      });
    });

    return objectCache[query.query.entity].values.toList();
  }

  dynamic instantiateObject(ClassMirror modelTypeMirror, _RowRange range, List<dynamic> objectValues) {
    Model model = modelTypeMirror.newInstance(new Symbol(""), []).reflectee;
    var propertyIterator = range.innerMappingElements.iterator;
    objectValues.forEach((value) {
      propertyIterator.moveNext();
      var key = propertyIterator.current.modelKey;
      if (propertyIterator.current.destinationEntity != null) {
        if (value != null) {
          model.dynamicBacking[key] = new _DelayedInstanceForeignKey(propertyIterator.current.destinationType,
              propertyIterator.current.destinationEntity, value);
        }
      } else {
        model.dynamicBacking[key] = value;
      }
    });
    return model;
  }

  Map<ModelEntity, _RowRange> rangeMapForQuery(_PostgresqlQuery query) {
    Map<ModelEntity, _RowRange> entityRowRangeMap = {};
    ModelEntity currentEntity;
    var startIndex = 0;
    var currentEntityPrimaryKey;
    var lastNoticedPrimaryKeyIndex = 0;
    for (int i = 0; i < query.resultMappingElements.length; i++) {
      var mapElement = query.resultMappingElements[i];
      if (currentEntity != mapElement.entity) {
        if (currentEntity != null) {
          entityRowRangeMap[currentEntity] = new _RowRange(startIndex,
              i - 1,
              lastNoticedPrimaryKeyIndex - startIndex,
              query.resultMappingElements);
        }
        startIndex = i;
        currentEntity = mapElement.entity;
        currentEntityPrimaryKey = currentEntity.primaryKey;
      }

      if (mapElement.modelKey == currentEntityPrimaryKey) {
        lastNoticedPrimaryKeyIndex = i;
      }
    }

    entityRowRangeMap[currentEntity] = new _RowRange(startIndex,
        query.resultMappingElements.length - 1,
        lastNoticedPrimaryKeyIndex - startIndex,
        query.resultMappingElements);
    return entityRowRangeMap;
  }

  Map<Type, String> expectedRelationshipsForQuery(Query q) {
    var m = {};
    q.subQueries?.forEach((k, subQuery) {
      m[q.modelType] = k;
      m.addAll(expectedRelationshipsForQuery(subQuery));
    });

    return m;
  }
}

class _RowRange {
  final int startIndex;
  final int endIndex;
  final int primaryKeyInnerIndex;
  List<_MappingElement> innerMappingElements;

  _RowRange(int sIndex, int eIndex, this.primaryKeyInnerIndex, List<_MappingElement> outerMappingElements) :
        startIndex = sIndex,
        endIndex = eIndex,
        innerMappingElements = outerMappingElements.sublist(sIndex, eIndex + 1);
}

class _DelayedInstanceForeignKey {
  final dynamic value;
  final ModelEntity entity;
  final Type type;
  _DelayedInstanceForeignKey(this.type, this.entity, this.value);
}*/