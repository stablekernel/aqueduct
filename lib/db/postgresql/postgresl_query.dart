part of monadart;

class _MappingElement {
  final String modelKey;
  final String databaseKey;

  const _MappingElement(this.modelKey, this.databaseKey);
}

class _PostgresqlQuery {
  PostgresqlSchema schema;
  Query query;
  String string;
  Map values = {};
  List<_MappingElement> resultMappingElements;

  void preprocess() {
    // Transfer predicateObject to predicate if one exists, overwrites the predicate.
    if (query.predicateObject != null) {
      query.predicate = predicateFromPredicateObject(query.predicateObject);
    }

    resultMappingElements = mappingElementsFromQuery(query);
    if (query.pageDescriptor != null) {
      // // select * from t where id < 11 order by id desc limit 5
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

  Predicate predicateFromPredicateObject(Model obj) {
    var m = columnValueMapForObject(obj);

    var predicateItems = [];
    m.forEach((k, v) {
      predicateItems.add("${k}=@${k}");
    });

    var predicateFmt = predicateItems.join(" and ");
    return new Predicate("(${predicateFmt.toString()})", m);
  }

  List<_MappingElement> mappingElementsFromQuery(Query query) {
    if (query.resultKeys == null) {
      var columns = schema.tables[query.modelType].columns;

      var elements = columns.keys
          .where((k) => columns[k].isRealColumn && !columns[k].shouldOmitFromDefaultSet)
          .map((modelKey) => new _MappingElement(modelKey, columns[modelKey].name));
      return elements.toList();
    }

    var columns = schema.tables[query.modelType].columns;
    var elements = query.resultKeys.map((modelKey) {
      var col = columns[modelKey];
      if (col == null) {
        throw new QueryException(
            500,
            "Attempting to retrieve $modelKey from ${MirrorSystem.getName(reflectType(query.modelType).simpleName)}, but that key doesn't exist.",
            -1);
      }
      return new _MappingElement(modelKey, columns[modelKey].name);
    });

    return elements.toList();
  }

  Map<String, dynamic> columnValueMapForObject(Model valueObject) {
    if (valueObject == null) {
      return {};
    }

    var type = reflect(valueObject).type.reflectedType;
    var table = schema.tables[type];
    var columns = table.columns;
    var m = {};

    valueObject.dynamicBacking.forEach((modelKey, value) {
      var column = columns[modelKey];
      var relationship = column.relationship;

      if (relationship != null) {
        if (relationship.type == RelationshipType.hasMany) {
          return;
        }

        var relatedValue = (value as Model).dynamicBacking[column.relationship.destinationModelKey];

        if (relatedValue == null) {
          var thisType = MirrorSystem.getName(reflect(valueObject).type.simpleName);

          var relatedType = MirrorSystem.getName(reflectType(column.relationship.destinationType).simpleName);

          throw new QueryException(
              500,
              "Query object of type ${thisType} contains embedded object of type ${relatedType},"
              "but embedded object does not contain foreign model key ${column.relationship.destinationModelKey}",
              -1);
        }

        m[column.name] = relatedValue;
      } else {
        m[column.name] = value;
      }
    });

    return m;
  }

  String orderByString() {
    if (query.sortDescriptors != null) {
      var transformFunc = (SortDescriptor sd) =>
          "${sd.key} ${(sd.order == SortDescriptorOrder.ascending ? "asc" : "desc")}";
      var joinedSortDescriptors = query.sortDescriptors.map(transformFunc).join(",");
      return joinedSortDescriptors;
    }
    return null;
  }

  List<String> resultColumnNames() {
    var table = schema.tables[query.modelType];
    var columns = table.columns;

    return resultMappingElements.map((e) {
      var column = columns[e.modelKey];
      if (column == null) {
        throw new QueryException(400, "column \"${e.databaseKey}\" does not exist", 42703);
      }
      return "${column.name}";
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
    queryStringBuffer.write("${schema.tables[query.modelType].name} ");
    queryStringBuffer.write("(${valueKeys.join(",")}) ");
    queryStringBuffer.write("values (${valueVariables.join(",")}) ");

    if (resultMappingElements != null) {
      var cols = resultColumnNames();
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

    var queryColumns = resultColumnNames();
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("select ${queryColumns.join(",")} ");
    queryStringBuffer.write("from ${schema.tables[query.modelType].name} ");

    if (query.predicate != null) {
      queryStringBuffer.write("where ${query.predicate.format} ");
      values = query.predicate.parameters;
    }

    // Add page to sort descriptors?

    var orderString = orderByString();
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
}

class _PostgresqlDeleteQuery extends _PostgresqlQuery {
  _PostgresqlDeleteQuery(PostgresqlSchema schema, Query query) {
    this.schema = schema;
    this.query = query;

    preprocess();

    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("delete from ${schema.tables[query.modelType].name} ");

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
    queryStringBuffer.write("update ${schema.tables[query.modelType].name} ");
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
      var cols = resultColumnNames();
      queryStringBuffer.write("returning ${cols.join(",")} ");
    }

    string = queryStringBuffer.toString();
    values = updateValues;
  }
}
