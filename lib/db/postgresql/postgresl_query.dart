part of monadart;

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
  PostgresqlSchema schema;
  Query query;
  String string;
  Map values = {};
  List<_MappingElement> resultMappingElements;

  void preprocess() {
    resultMappingElements = mappingElementsFromQuery(schema, query);
    if (query.pageDescriptor != null) {
      if (query.pageDescriptor.referenceValue != null) {
        var operator = (query.pageDescriptor.direction == PageDirection.after ? ">" : "<");
        var pagePredicate = new Predicate("${query.pageDescriptor.referenceKey} ${operator} @inq_page_value",
            {"inq_page_value": query.pageDescriptor.referenceValue});
        if (query.predicate != null) {
          query.predicate = Predicate.andPredicates([pagePredicate, query.predicate]);
        } else {
          query.predicate = pagePredicate;
        }
      }

      var order = (query.pageDescriptor.direction == PageDirection.after
          ? SortDescriptorOrder.ascending
          : SortDescriptorOrder.descending);
      var sortDescriptor = new SortDescriptor(query.pageDescriptor.referenceKey, order);
      if (query.sortDescriptors != null) {
        query.sortDescriptors.insert(0, sortDescriptor);
      } else {
        query.sortDescriptors = [sortDescriptor];
      }
    }
  }

  static List<_MappingElement> mappingElementsFromQuery(PostgresqlSchema sqlSchema, Query query) {
    var mapElements = [];

    var table = sqlSchema.tables[query.modelType];
    if (query.resultKeys == null) {
      var columns = table.columns;

      mapElements.addAll(columns.keys
          .where((k) => columns[k].isRealColumn && !columns[k].shouldOmitFromDefaultSet)
          .map((modelKey) => new _MappingElement(query.modelType,
            query.entity,
            modelKey,
            "${table.name}.${columns[modelKey].name}",
            columns[modelKey].relationship?.destinationType,
            columns[modelKey].relationship?.entity)));
    } else {
      var columns = table.columns;
      var elements = query.resultKeys.map((modelKey) {
        var col = columns[modelKey];
        if (col == null) {
          throw new QueryException(500, "Attempting to retrieve $modelKey from ${query.modelType}, but that key doesn't exist.", -1);
        }

        var columnKey = columns[modelKey].name;
        return new _MappingElement(query.modelType,
            query.entity, modelKey,
            "${table.name}.$columnKey",
            columns[modelKey].relationship?.destinationType,
            columns[modelKey].relationship?.entity);
      });
      mapElements.addAll(elements);
    }

    if (query.subQueries != null) {
      query.subQueries.forEach((_, subquery) {
        mapElements.addAll(_PostgresqlQuery.mappingElementsFromQuery(sqlSchema, subquery));
      });
    }
    return mapElements;
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

      if (relationship != null) {
        if (relationship.type == RelationshipType.hasMany) {
          return;
        }

        if (value != null) {
          Model innerModel = value;
          var relatedValue = innerModel.dynamicBacking[column.relationship.destinationModelKey];

          if (relatedValue == null) {
            var thisType = MirrorSystem.getName(reflect(valueObject).type.simpleName);

            var relatedType = MirrorSystem.getName(reflectType(column.relationship.destinationType).simpleName);

            throw new QueryException(500, "Query object of type ${thisType} contains embedded object of type ${relatedType},"
                                    "but embedded object does not contain foreign model key ${column.relationship.destinationModelKey}",
                                    -1);
          }

          m[column.name] = relatedValue;
        } else {
          m[column.name] = null;
        }
      } else {
        m[column.name] = value;
      }
    });

    return m;
  }

  String get orderByString {
    if (query.sortDescriptors != null) {
      var transformFunc = (SortDescriptor sd) =>
          "${sd.key} ${(sd.order == SortDescriptorOrder.ascending ? "asc" : "desc")}";
      var joinedSortDescriptors = query.sortDescriptors.map(transformFunc).join(",");
      return joinedSortDescriptors;
    }
    return null;
  }

  List<String> get resultColumnNames {
    return resultMappingElements.map((e) {
      return e.databaseKey;
    }).toList();
  }
}

class _PostgresqlInsertQuery extends _PostgresqlQuery {
  _PostgresqlInsertQuery(PostgresqlSchema schema, Query query) {
    this.schema = schema;
    this.query = query;

    preprocess();

    Map insertValues = (query.values != null ? query.values : columnValueMapForObject(query.valueObject));

    var valueKeys = insertValues.keys;
    var valueVariables = valueKeys.map((k) => "@${k}");

    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("insert into ");
    queryStringBuffer.write("${query.entity.tableName} ");
    queryStringBuffer.write("(${valueKeys.join(",")}) ");
    queryStringBuffer.write("values (${valueVariables.join(",")}) ");

    if (resultMappingElements != null) {
      var cols = resultColumnNames;
      queryStringBuffer.write("returning ${cols.join(",")} ");
    }

    string = queryStringBuffer.toString();
    values = insertValues;
  }
}

class _PostgresqlFetchQuery extends _PostgresqlQuery {
  _PostgresqlFetchQuery(PostgresqlSchema schema, Query query) {
    this.schema = schema;
    this.query = query;

    preprocess();

    var queryColumns = resultColumnNames;
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("select ${queryColumns.join(",")} ");
    queryStringBuffer.write("from ${query.entity.tableName} ");

    joinStrings?.forEach((str) {
      queryStringBuffer.write(" $str ");
    });

    if (query.predicate != null) {
      queryStringBuffer.write("where ${query.predicate.format} ");
      values = query.predicate.parameters;
    }

    // Add page to sort descriptors?

    var orderString = orderByString;
    if (orderString != null) {
      queryStringBuffer.write("order by ${orderString} ");
    }

    if (query.fetchLimit != 0) {
      queryStringBuffer.write("limit ${query.fetchLimit} ");
    }

    if (query.offset != 0) {
      queryStringBuffer.write("offset ${query.offset} ");
    }

    string = queryStringBuffer.toString();
  }

  List<String> get joinStrings {
    if (query.subQueries == null || query.subQueries.length == 0) {
      return null;
    }
    var cmds = query.subQueries.keys.map((subqueryPropertyKey) {
      var thisJoin = joinStringsForQuery(subqueryPropertyKey, query);
      return thisJoin;
    });

    return cmds.expand((element) => element).toList();
  }

  static List<String> joinStringsForQuery(String subqueryPropertyKey, Query query) {
    var subquery = query.subQueries[subqueryPropertyKey];
    var propertyMirror = query.entity._propertyMirrorForProperty(subqueryPropertyKey);
    var joinTableName = subquery.entity.tableName;
    var relationship = subquery.entity._relationshipAttributeForPropertyMirror(propertyMirror);
    var propertyNameOnJoinEntity = relationship.inverseKey;
    var foreignKey = subquery.entity.foreignKeyForProperty(propertyNameOnJoinEntity);
    var referencedKey = relationship.referenceKey ?? query.entity.primaryKey;

    var thisQuery = ["left outer join $joinTableName on (${query.entity.tableName}.${referencedKey}=${joinTableName}.$foreignKey)"];

    var subqueryJoins = subquery.subQueries?.keys?.map((k) => joinStringsForQuery(k, subquery))?.toList();
    if (subqueryJoins != null) {
      var expanded = subqueryJoins.expand((e) => e).toList();
      thisQuery.addAll(expanded);
    }
    return thisQuery;
  }
}

class _PostgresqlDeleteQuery extends _PostgresqlQuery {
  _PostgresqlDeleteQuery(PostgresqlSchema schema, Query query) {
    this.schema = schema;
    this.query = query;

    preprocess();

    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("delete from ${query.entity.tableName} ");

    if (query.predicate != null) {
      queryStringBuffer.write("where ${query.predicate.format} ");
      values = query.predicate.parameters;
    }

    string = queryStringBuffer.toString();
  }
}

class _PostgresqlUpdateQuery extends _PostgresqlQuery {
  _PostgresqlUpdateQuery(PostgresqlSchema schema, Query query) {
    this.schema = schema;
    this.query = query;

    preprocess();

    Map updateValues = (query.values != null ? query.values : columnValueMapForObject(query.valueObject));

    var keys = updateValues.keys;
    var setPairs = keys.map((k) => "${k}=@${k}");

    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("update ${query.entity.tableName} ");
    queryStringBuffer.write("set ${setPairs.join(",")} ");

    if (query.predicate != null) {
      // Need to prefix predicate parameters to avoid conflicting with update parameters
      var format = query.predicate.format.replaceAll("@", "@p_");
      var formattedMap = {};
      query.predicate.parameters.forEach((k, v) {
        formattedMap["p_${k}"] = v;
      });
      updateValues.addAll(formattedMap);

      queryStringBuffer.write("where ${format} ");
    }

    if (resultMappingElements != null) {
      var cols = resultColumnNames;
      queryStringBuffer.write("returning ${cols.join(",")} ");
    }

    string = queryStringBuffer.toString();
    values = updateValues;
  }
}
