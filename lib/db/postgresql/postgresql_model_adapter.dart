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
    _PostgresqlQuery pgsqlQuery = new _PostgresqlQuery(schema, query);
    pgsqlQuery.logger = logger;

    var statement = pgsqlQuery.statement;
    statement.compile();

    var formatString = statement.formatString;
    var formatParameters = statement.formatParameters;

    return new Future(() async {
      try {
        var conn = await getDatabaseConnection();
        if (pgsqlQuery.resultColumnNames != null && pgsqlQuery.resultColumnNames.length > 0) {
          var results = await conn.query(formatString, formatParameters).toList();
          logger?.info("Inquirer: Querying $formatString $formatParameters -- Yielded: $results");

          return mapRowsAccordingToQuery(results, pgsqlQuery);
        } else {
          var result = await conn.execute(formatString, formatParameters);
          logger?.info("Inquirer: Executing $formatString $formatParameters -- Yielded: $result");

          return result;
        }
      } on PostgresqlException catch (e, stackTrace) {
        logger.info("Inquirer: SQL Failed $formatString $formatParameters");
        throw interpretException(e, stackTrace);
      } on QueryException {
        logger.info("Inquirer: Query Failed $formatString $formatParameters");
        rethrow;
      } catch (e, stackTrace) {
        logger.info("Inquirer: Unknown Failure $formatString $formatParameters");
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
}