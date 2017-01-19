import 'dart:async';

import '../db.dart';
// todo: wow get rid of this
import '../managed/query_matchable.dart';
import '../managed/instantiator.dart';
import 'postgresql_column.dart';

class PostgresQuery<InstanceType extends ManagedObject> extends Object with QueryMixin<InstanceType> implements Query<InstanceType> {

  PostgresQuery(this.context);

  ManagedContext context;

  ManagedInstantiator createMapper() {
    var rowMapper = new ManagedInstantiator(entity);
    rowMapper.properties = resultProperties;

    if (hasMatcher) {
      if (matchOn.hasJoinElements) {
        if (pageDescriptor != null) {
          throw new QueryException(QueryExceptionEvent.requestFailure,
              message:
              "Query cannot have properties that are includeInResultSet and also have a pageDescriptor.");
        }

        var joinElements = joinElementsFromQueryMatchable(
            matchOn, context.persistentStore, nestedResultProperties);
        rowMapper.addJoinElements(joinElements);
      }
    }

    return rowMapper;
  }

  Future<InstanceType> insert() async {
    var rowMapper = createMapper();

    var propertyValueMap = rowMapper.propertyValueMap((valueMap ?? values?.backingMap));
    var propertyValueKeys = propertyValueMap.keys;

    var buffer = new StringBuffer();
    buffer.write("INSERT INTO ${entity.tableName} ");
    buffer.write("(${columnListString(propertyValueKeys)}) ");
    buffer.write("VALUES (${columnListString(propertyValueKeys, typed: true, prefix: "@")}) ");

    if ((rowMapper.orderedMappingElements?.length ?? 0) > 0) {
      buffer.write("RETURNING ${columnListString(rowMapper.orderedMappingElements.map((c) => c.property))}");
    }

    var substitutionValues = <String, dynamic>{};
    propertyValueMap.forEach((k, v) {
      substitutionValues[columnNameForProperty(k)] = v;
    });

    var results = await context.persistentStore.executeQuery(
        buffer.toString(), substitutionValues, timeoutInSeconds);

    return rowMapper.instancesForRows(results).first;
  }

  Future<List<InstanceType>> update() async {
    var rowMapper = createMapper();

    if (predicate == null &&
        !confirmQueryModifiesAllInstancesOnDeleteOrUpdate) {
      throw new QueryException(QueryExceptionEvent.internalFailure,
          message:
          "Query would impact all records. This could be a destructive error. Set confirmQueryModifiesAllInstancesOnDeleteOrUpdate on the Query to execute anyway.");
    }

    var prefix = "u_";
    var propertyValueMap = rowMapper.propertyValueMap((valueMap ?? values?.backingMap));
    var propertyValueKeys = propertyValueMap.keys;

    var updateValueMap = <String, dynamic>{};
    propertyValueMap.forEach((k, v) {
      updateValueMap[columnNameForProperty(k, prefix: prefix)] = v;
    });

    var setPairString = propertyValueKeys.map((m) {
      var name = columnNameForProperty(m);
      var typedName = columnNameForProperty(m, typed: true, prefix: "$prefix");
      return "$name=@$typedName";
    }).join(",");

    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("UPDATE ${entity.tableName} SET $setPairString ");

    if (predicate != null) {
      queryStringBuffer.write("WHERE ${predicate.format} ");
      updateValueMap.addAll(predicate.parameters);
    }

    if ((rowMapper.orderedMappingElements?.length ?? 0) > 0) {
      queryStringBuffer.write("RETURNING ${columnListString(rowMapper.orderedMappingElements.map((c) => c.property))}");
    }

    var results = await context.persistentStore.executeQuery(
        queryStringBuffer.toString(), updateValueMap, timeoutInSeconds);

    return rowMapper.instancesForRows(results);  }

  Future<InstanceType> updateOne() async {
    var results = await update();
    if (results.length == 1) {
      return results.first;
    } else if (results.length == 0) {
      return null;
    }

    throw new QueryException(QueryExceptionEvent.internalFailure,
        message:
        "updateOne modified more than one row, this is a serious error.");
  }

  Future<int> delete() async {
    if (predicate == null && !confirmQueryModifiesAllInstancesOnDeleteOrUpdate) {
      throw new QueryException(QueryExceptionEvent.internalFailure,
          message:
          "Query would impact all records. This could be a destructive error. Set confirmQueryModifiesAllInstancesOnDeleteOrUpdate on the Query to execute anyway.");
    }

    var buffer = new StringBuffer();
    buffer.write("DELETE FROM ${entity.tableName} ");

    if (predicate != null) {
      buffer.write("WHERE ${predicate.format} ");
    }

    return context.persistentStore.executeQuery(
        buffer.toString(), predicate?.parameters, timeoutInSeconds,
        shouldReturnCountOfRowsAffected: true);
  }

  Future<List<InstanceType>> fetch() async {
    var rowMapper = createMapper();

    return _fetch(rowMapper);
  }


  // todo: remove duplicates from joinedFetch

  Future<List<InstanceType>> _fetch(ManagedInstantiator rowMapper) async {
    if (rowMapper.orderedMappingElements.any((c) => c is PropertyToRowMapping)) {
      return joinedFetch(rowMapper);
    }

    var combinedPredicates = [predicate, _pagePredicateForQuery]
        .where((p) => p != null)
        .toList();
    var allPredicates = QueryPredicate.andPredicates(combinedPredicates);

    var buffer = new StringBuffer();
    buffer.write("SELECT ${columnListString(rowMapper.orderedMappingElements.map((c) => c.property))} ");
    buffer.write("FROM ${entity.tableName} ");

    if (allPredicates != null) {
      buffer.write("WHERE ${allPredicates.format} ");
    }

    buffer.write("$_orderByStringForQuery ");

    if (fetchLimit != 0) {
      buffer.write("LIMIT ${fetchLimit} ");
    }

    if (offset != 0) {
      buffer.write("OFFSET ${offset} ");
    }

    var results = await context.persistentStore.executeQuery(
        buffer.toString(), allPredicates?.parameters, timeoutInSeconds);

    return rowMapper.instancesForRows(results);
  }

  Future<List<InstanceType>> joinedFetch(ManagedInstantiator rowMapper) async {
    var predicateValueMap = <String, dynamic>{};
    var joinElements = rowMapper.orderedMappingElements
        .where((mapElement) => mapElement is PropertyToRowMapping)
        .map((mapElement) => mapElement as PropertyToRowMapping);

    var columnsToFetch = rowMapper.flattenedMappingElements.map((mapElement) {
        return columnNameForProperty(mapElement.property, includeTableName: true);
    }).join(",");

    var buffer = new StringBuffer("SELECT $columnsToFetch FROM ${entity.tableName} ");

    var joinWriter = (PropertyToRowMapping j) {
      buffer.write("${_joinStringForJoin(j)} ");
      if (j.predicate != null) {
        predicateValueMap.addAll(j.predicate.parameters);
      }
    };
    joinElements.forEach((joinElement) {
      joinWriter(joinElement);
      joinElement.orderedNestedRowMappings.forEach((j) {
        joinWriter(j);
      });
    });

    if (predicate != null) {
      buffer.write("WHERE ${predicate.format} ");
      predicateValueMap.addAll(predicate.parameters);
    }

    buffer.write("$_orderByStringForQuery ");

    if (fetchLimit != 0) {
      buffer.write("LIMIT ${fetchLimit} ");
    }

    if (offset != 0) {
      buffer.write("OFFSET ${offset} ");
    }

    var results = await context.persistentStore.executeQuery(
        buffer.toString(), predicateValueMap, timeoutInSeconds);

    return rowMapper.instancesForRows(results);
  }

  Future<InstanceType> fetchOne() async {
    var rowMapper = createMapper();

    if (!rowMapper.orderedMappingElements.any((c) => c is PropertyToRowMapping)) {
      fetchLimit = 1;
    }

    var results = await _fetch(rowMapper);
    if (results.length == 1) {
      return results.first;
    } else if (results.length > 1) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
          "Query expected to fetch one instance, but ${results.length} instances were returned.");
    }
    return null;
  }

  void validatePageDescriptor() {
    if (pageDescriptor == null) {
      return null;
    }

    var prop = entity.attributes[pageDescriptor.propertyName];
    if (prop == null) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
          "Property ${pageDescriptor.propertyName} in pageDescriptor does not exist on ${entity.tableName}.");
    }

    if (pageDescriptor.boundingValue != null &&
        !prop.isAssignableWith(pageDescriptor.boundingValue)) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
          "Property ${pageDescriptor.propertyName} in pageDescriptor has invalid type (${pageDescriptor.boundingValue.runtimeType}).");
    }
  }

  String get _orderByStringForQuery {
    List<QuerySortDescriptor> sortDescs = sortDescriptors ?? [];

    if (pageDescriptor != null) {
      var pageSortDescriptor = new QuerySortDescriptor(
          pageDescriptor.propertyName, pageDescriptor.order);
      sortDescs.insert(0, pageSortDescriptor);
    }

    if (sortDescs.length == 0) {
      return "";
    }

    var joinedSortDescriptors = sortDescs.map((QuerySortDescriptor sd) {
      var property = entity.properties[sd.key];
      var columnName = columnNameForProperty(property, includeTableName: true);
      var order = (sd.order == QuerySortOrder.ascending ? "ASC" : "DESC");

      return "$columnName $order";
    }).join(",");

    return "ORDER BY $joinedSortDescriptors";
  }

  // todo: this sucks
  QueryPredicate get _pagePredicateForQuery {
    validatePageDescriptor();
    if (pageDescriptor?.boundingValue == null) {
      return null;
    }

    var pagingProperty = entity.properties[pageDescriptor.propertyName];
    var operator = (pageDescriptor.order == QuerySortOrder.ascending ? ">" : "<");
    var prefix = "aq_page_";

    var columnName = columnNameForProperty(pagingProperty, includeTableName: true);
    var variableName = columnNameForProperty(pagingProperty, prefix: prefix);

    return new QueryPredicate("$columnName ${operator} @$variableName${typeSuffix(pagingProperty)}", {
      variableName: pageDescriptor.boundingValue
    });
  }

  // todo: this sucks
  List<PropertyToRowMapping> joinElementsFromQueryMatchable(
      QueryMatchableExtension matcherBackedObject,
      PersistentStore store,
      Map<Type, List<String>> nestedResultProperties) {
        var entity = matcherBackedObject.entity;
        var propertiesToJoin = matcherBackedObject.joinPropertyKeys;

        return propertiesToJoin
            .map((propertyName) {
              QueryMatchableExtension inner =
              matcherBackedObject.backingMap[propertyName];

              var relDesc = entity.relationships[propertyName];
              var predicate = predicateFromMatcherBackedObject(inner);
              var nestedProperties =
              nestedResultProperties[inner.entity.instanceType.reflectedType];
              var propertiesToFetch =
                  nestedProperties ?? inner.entity.defaultProperties;

              var joinElement = new PropertyToRowMapping(
                  PersistentJoinType.leftOuter,
                  relDesc,
                  predicate,
                  PropertyToColumnMapper.mappersForKeys(inner.entity, propertiesToFetch));
              if (inner.hasJoinElements) {
                joinElement.orderedMappingElements.addAll(joinElementsFromQueryMatchable(
                    inner, store, nestedResultProperties));
              }

              return joinElement;
            })
            .toList();
  }


  // this all sucks
  String _joinStringForJoin(PropertyToRowMapping ji) {
    var parentEntity = ji.property.entity;
    var parentProperty = parentEntity.properties[parentEntity.primaryKey];

    var predicate = new QueryPredicate(
        "${columnNameForProperty(parentProperty, includeTableName: true)}=${columnNameForProperty(ji.joinProperty, includeTableName: true)}",
        {});

    if (ji.predicate != null) {
      predicate = QueryPredicate.andPredicates([predicate, ji.predicate]);
    }

    return "${_stringForJoinType(ji.type)} JOIN ${ji.joinProperty.entity.tableName} ON ${predicate.format}";
  }

  String _stringForJoinType(PersistentJoinType t) {
    switch (t) {
      case PersistentJoinType.leftOuter:
        return "LEFT OUTER";
    }
    return null;
  }

  @override
  QueryPredicate comparisonPredicate(ManagedPropertyDescription desc,
      MatcherOperator operator, dynamic value) {
    var prefix = "${desc.entity.tableName}_";
    var columnName = columnNameForProperty(desc, includeTableName: true);
    var variableName = columnNameForProperty(desc, prefix: prefix);

    return new QueryPredicate("$columnName ${symbolTable[operator]} @$variableName${typeSuffix(desc)}", {
      variableName: value
    });
  }

  @override
  QueryPredicate containsPredicate(
      ManagedPropertyDescription desc, Iterable<dynamic> values) {
    var tableName = desc.entity.tableName;
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "ctns${tableName}_${counter}_";

      var variableName = columnNameForProperty(desc, prefix: prefix);
      tokenList.add("@$variableName${typeSuffix(desc)}");
      pairedMap[variableName] = value;

      counter++;
    });

    var columnName = columnNameForProperty(desc, includeTableName: true);
    return new QueryPredicate("$columnName IN (${tokenList.join(",")})",
        pairedMap);
  }

  @override
  QueryPredicate nullPredicate(ManagedPropertyDescription desc, bool isNull) {
    var columnName = columnNameForProperty(desc, includeTableName: true);
    return new QueryPredicate(
        "$columnName ${isNull ? "ISNULL" : "NOTNULL"}", {});
  }

  @override
  QueryPredicate rangePredicate(ManagedPropertyDescription desc,
      dynamic lhsValue, dynamic rhsValue, bool insideRange) {
    var columnName = columnNameForProperty(desc, includeTableName: true);
    var lhsName = columnNameForProperty(desc, prefix: "${desc.entity.tableName}_lhs_");
    var rhsName = columnNameForProperty(desc, prefix: "${desc.entity.tableName}_rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return new QueryPredicate(
        "$columnName $operation @$lhsName${typeSuffix(desc)} AND @$rhsName${typeSuffix(desc)}", {
      lhsName: lhsValue, rhsName: rhsValue
    });
  }

  @override
  QueryPredicate stringPredicate(ManagedPropertyDescription desc,
      StringMatcherOperator operator, dynamic value) {
    var prefix = "${desc.entity.tableName}_";
    var columnName = columnNameForProperty(desc, includeTableName: true);
    var variableName = columnNameForProperty(desc, prefix: prefix);

    var matchValue = value;
    switch (operator) {
      case StringMatcherOperator.beginsWith:
        matchValue = "$value%";
        break;
      case StringMatcherOperator.endsWith:
        matchValue = "%$value";
        break;
      case StringMatcherOperator.contains:
        matchValue = "%$value%";
        break;
    }

    return new QueryPredicate("$columnName LIKE @$variableName${typeSuffix(desc)}", {
      variableName: matchValue
    });
  }
}