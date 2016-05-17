part of aqueduct;

class _MappingElement {
  final String modelKey;
  final String databaseKey;
  final Type modelType;
  final Type destinationType;
  final ModelEntity entity;
  final ModelEntity destinationEntity;

  const _MappingElement(this.modelType, this.entity, this.modelKey, this.databaseKey, this.destinationType, this.destinationEntity);

  String toString() {
    return "$modelType.$modelKey -> $databaseKey";
  }
}

class _PostgresqlQuery {
  static List<_MappingElement> mappingElementsFromQuery(PostgresqlSchema sqlSchema, Query query) {
    var mapElements = [];

    var table = sqlSchema.tables[query.modelType];
    var columns = table.columns;
    var columnKeys = query.resultKeys ?? columns.keys
        .where((k) => columns[k].isRealColumn && !columns[k].shouldOmitFromDefaultSet).toList();

    mapElements.addAll(columnKeys.map((modelKey) {
      var column = columns[modelKey];
      if (column == null) {
        throw new QueryException(500, "Attempting to retrieve $modelKey from ${query.modelType}, but that key doesn't exist.", -1);
      }
      var relationship = column.relationship;
      return new _MappingElement(query.modelType, query.entity, modelKey, "${table.name}.${column.name}", relationship?.destinationType, relationship?.entity);
    }));

    query.subQueries?.forEach((_, subquery) {
      mapElements.addAll(_PostgresqlQuery.mappingElementsFromQuery(sqlSchema, subquery));
    });

    return mapElements;
  }

  _PostgresqlQuery(this.schema, this.query) {
    if (query.queryType == QueryType.fetch || query.queryType == QueryType.insert || query.queryType == QueryType.update) {
      resultMappingElements = mappingElementsFromQuery(schema, query);
    }
  }

  Logger logger;
  PostgresqlSchema schema;
  List<_MappingElement> resultMappingElements;
  Query query;

  _PostgresqlStatement get statement {
    Map queryValues = query.values ?? columnValueMapForObject(query.valueObject);
    var pred = this.predicate;

    return new _PostgresqlStatement()
        ..command = query.queryType
        ..tableName = query.entity.tableName
        ..insertValueMap = queryValues
        ..queryValueMap = pred.parameters
        ..whereClause = pred?.format
        ..sortDescriptors = sortDescriptors
        ..resultColumnNames = resultColumnNames
        ..limitCount = query.fetchLimit
        ..offsetCount = query.offset
        ..formatParameters = queryValues
        ..joinStatements = _joinStatementsForQuery(query);
  }

  Predicate get predicate {
    var pagePred = pagePredicate;
    var queryPred = query.predicate;

    return Predicate.andPredicates([pagePred, queryPred].where((p) => p != null).toList());
  }

  Predicate get pagePredicate {
    if(query.pageDescriptor?.referenceValue == null) {
      return null;
    }

    var operator = (query.pageDescriptor.direction == PageDirection.after ? ">" : "<");
    return new Predicate("${query.pageDescriptor.referenceKey} ${operator} @inq_page_value",
        {"inq_page_value": query.pageDescriptor.referenceValue});
  }

  List<SortDescriptor> get sortDescriptors {
    List<SortDescriptor> sortDescs = query.sortDescriptors ?? [];
    var pageSortDesc = pageSortDescriptor;
    if (pageSortDescriptor != null) {
      sortDescs.add(pageSortDesc);
    }

    return sortDescs;
  }

  SortDescriptor get pageSortDescriptor {
    if (query.pageDescriptor == null) {
      return null;
    }

    var order = (query.pageDescriptor.direction == PageDirection.after
        ? SortDescriptorOrder.ascending
        : SortDescriptorOrder.descending);

    return new SortDescriptor(query.pageDescriptor.referenceKey, order);
  }

  List<String> get resultColumnNames {
    return resultMappingElements?.map((e) {
      return e.databaseKey;
    })?.toList();
  }

  Map<String, dynamic> columnValueMapForObject(Model valueObject) {
    if (valueObject == null) {
      return {};
    }

    var table = schema.tables[query.modelType];
    var columns = table.columns;
    var m = {};

    valueObject.dynamicBacking.forEach((modelKey, value) {
      var column = columns[modelKey];
      var relationship = column.relationship;
      var proposedValue = value;

      if (relationship != null) {
        if (relationship.type != RelationshipType.belongsTo) {
          return;
        }

        m[column.name] = _foreignKeyValueForProperty(relationship, value, valueObject, column);
      } else {
        m[column.name] = proposedValue;
      }
    });

    return m;
  }

  dynamic _foreignKeyValueForProperty(_PostgresqlRelationship relationship, dynamic value, dynamic valueObject, _PostgresqlColumn column) {
    if (value != null) {
      Model innerModel = value;
      var relatedValue = innerModel.dynamicBacking[relationship.destinationModelKey];

      if (relatedValue == null) {
        var thisType = MirrorSystem.getName(reflect(valueObject).type.simpleName);
        var relatedType = MirrorSystem.getName(reflectType(column.relationship.destinationType).simpleName);
        throw new QueryException(500, "Query object of type ${thisType} contains instance of type ${relatedType},"
            "but this instance does not contain value for foreign model key ${column.relationship.destinationModelKey}", -1);
      }

      return relatedValue;
    }

    return null;
  }

  static List<_PostgresqlStatement> _joinStatementsForQuery(Query query) {
    var allSubqueries = query.subQueries?.keys?.map((subqueryPropertyKey) {
      var subquery = query.subQueries[subqueryPropertyKey];
      var propertyMirror = query.entity._propertyMirrorForProperty(subqueryPropertyKey);
      var joinTableName = subquery.entity.tableName;
      var relationship = subquery.entity._relationshipAttributeForPropertyMirror(propertyMirror);
      var propertyNameOnJoinEntity = relationship.inverseKey;
      var foreignKey = subquery.entity.foreignKeyForProperty(propertyNameOnJoinEntity);
      var referencedKey = relationship.referenceKey ?? query.entity.primaryKey;

      var pred = subquery.predicate;
      var statements = [new _PostgresqlStatement()
        ..command = QueryType.join
        ..tableName = query.entity.tableName
        ..joinTableReferenceKey = referencedKey
        ..joinTableName = joinTableName
        ..joinType = "left outer"
        ..joinTableForeignKey = foreignKey
        ..whereClause = pred?.format
        ..queryValueMap = pred?.parameters
      ];

      var subqueryJoins = subquery.subQueries?.keys?.map((k) => _joinStatementsForQuery(subquery))?.toList();
      if (subqueryJoins != null) {
        var expanded = subqueryJoins.expand((e) => e).toList();
        statements.addAll(expanded);
      }
      return statements;
    })?.toList();

    return allSubqueries?.expand((i) => i)?.toList();
  }
}