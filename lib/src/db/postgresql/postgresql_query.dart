import 'dart:async';

import '../db.dart';
import '../query/mixin.dart';
import '../query/mapper.dart';
import 'postgresql_mapping.dart';

// todo: wow get rid of this
import '../managed/query_matchable.dart';
import '../managed/instantiator.dart';

class PostgresQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>, PostgresMapper
    implements Query<InstanceType> {
  PostgresQuery(this.context);

  ManagedContext context;

  @override
  Future<InstanceType> insert() async {
    var rowMapper = createMapper();

    var propertyValueMap =
        rowMapper.translateValueMap((valueMap ?? values?.backingMap));
    var propertyValueKeys = propertyValueMap.keys;

    var buffer = new StringBuffer();
    buffer.write("INSERT INTO ${entity.tableName} ");
    buffer.write("(${columnListString(propertyValueKeys)}) ");
    buffer.write(
        "VALUES (${columnListString(propertyValueKeys, withTypeSuffix: true, withPrefix: "@")}) ");

    if ((rowMapper.orderedMappingElements?.length ?? 0) > 0) {
      buffer.write(
          "RETURNING ${columnListString(rowMapper.orderedMappingElements.map((c) => c.property))}");
    }

    var substitutionValues = <String, dynamic>{};
    propertyValueMap.forEach((k, v) {
      substitutionValues[columnNameForProperty(k)] = v;
    });

    var results = await context.persistentStore
        .executeQuery(buffer.toString(), substitutionValues, timeoutInSeconds);

    return rowMapper.instancesForRows(results).first;
  }

  @override
  Future<List<InstanceType>> update() async {
    var rowMapper = createMapper();

    if (predicate == null &&
        !confirmQueryModifiesAllInstancesOnDeleteOrUpdate) {
      throw new QueryException(QueryExceptionEvent.internalFailure,
          message:
              "Query would impact all records. This could be a destructive error. Set confirmQueryModifiesAllInstancesOnDeleteOrUpdate on the Query to execute anyway.");
    }

    var prefix = "u_";
    var propertyValueMap =
        rowMapper.translateValueMap((valueMap ?? values?.backingMap));
    var propertyValueKeys = propertyValueMap.keys;

    var updateValueMap = <String, dynamic>{};
    propertyValueMap.forEach((k, v) {
      updateValueMap[columnNameForProperty(k, withPrefix: prefix)] = v;
    });

    var assignments = propertyValueKeys.map((m) {
      var name = columnNameForProperty(m);
      var typedName = columnNameForProperty(m, withTypeSuffix: true, withPrefix: "$prefix");
      return "$name=@$typedName";
    }).join(",");

    var buffer = new StringBuffer();
    buffer.write("UPDATE ${entity.tableName} SET $assignments ");

    if (predicate != null) {
      buffer.write("WHERE ${predicate.format} ");
      if (predicate.parameters != null) {
        updateValueMap.addAll(predicate.parameters);
      }
    }

    if ((rowMapper.orderedMappingElements?.length ?? 0) > 0) {
      buffer.write(
          "RETURNING ${columnListString(rowMapper.orderedMappingElements.map((c) => c.property))}");
    }

    var results = await context.persistentStore
        .executeQuery(buffer.toString(), updateValueMap, timeoutInSeconds);

    return rowMapper.instancesForRows(results);
  }

  @override
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

  @override
  Future<int> delete() async {
    if (predicate == null &&
        !confirmQueryModifiesAllInstancesOnDeleteOrUpdate) {
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
        returnType: PersistentStoreQueryReturnType.rowCount);
  }

  @override
  Future<InstanceType> fetchOne() async {
    var rowMapper = createMapper();

    if (!rowMapper.orderedMappingElements
        .any((c) => c is PropertyToRowMapper)) {
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

  @override
  Future<List<InstanceType>> fetch() async {
    var rowMapper = createMapper();

    return _fetch(rowMapper);
  }

  //////

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

        var joinElements = joinElementsFromQueryMatchable(matchOn);
        rowMapper.addJoinElements(joinElements);
      }
    }

    return rowMapper;
  }

  Future<List<InstanceType>> _fetch(ManagedInstantiator rowMapper) async {
    var joinElements = rowMapper.orderedMappingElements
        .where((mapElement) => mapElement is PropertyToRowMapper)
        .map((mapElement) => mapElement as PropertyToRowMapper)
        .toList();
    var hasJoins = joinElements.isNotEmpty;

    var columnsToFetch = rowMapper.flattenedMappingElements.map((mapElement) {
      return columnNameForProperty(mapElement.property,
          withTableNamespace: hasJoins);
    }).join(",");

    var combinedPredicates =
        [predicate, pagingPredicate].where((p) => p != null).toList();
    var allPredicates = QueryPredicate.andPredicates(combinedPredicates);

    var buffer = new StringBuffer();
    buffer.write("SELECT $columnsToFetch ");
    buffer.write("FROM ${entity.tableName} ");

    Map<String, dynamic> joinVariables = {};
    if (hasJoins) {
      var joinWriter = (PropertyToRowMapper j) {
        buffer.write("${joinStringForJoin(j)} ");
        if (j.predicate?.parameters != null) {
          joinVariables.addAll(j.predicate.parameters);
        }
      };

      joinElements.forEach((joinElement) {
        joinWriter(joinElement);
        joinElement.orderedNestedRowMappings.forEach((j) {
          joinWriter(j);
        });
      });
    }

    if (allPredicates != null) {
      buffer.write("WHERE ${allPredicates.format} ");
    }

    buffer.write("$orderByString ");

    if (fetchLimit != 0) {
      buffer.write("LIMIT ${fetchLimit} ");
    }

    if (offset != 0) {
      buffer.write("OFFSET ${offset} ");
    }

    var variables = allPredicates?.parameters ?? {};
    if (hasJoins) {
      variables.addAll(joinVariables);
    }

    var results = await context.persistentStore
        .executeQuery(buffer.toString(), variables, timeoutInSeconds);

    return rowMapper.instancesForRows(results);
  }

  void validatePageDescriptor() {
    if (pageDescriptor == null) {
      return;
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

  String get orderByString {
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
      var columnName = columnNameForProperty(property, withTableNamespace: true);
      var order = (sd.order == QuerySortOrder.ascending ? "ASC" : "DESC");

      return "$columnName $order";
    }).join(",");

    return "ORDER BY $joinedSortDescriptors";
  }

  QueryPredicate get pagingPredicate {
    validatePageDescriptor();

    if (pageDescriptor?.boundingValue == null) {
      return null;
    }

    var pagingProperty = entity.properties[pageDescriptor.propertyName];
    var operator =
        (pageDescriptor.order == QuerySortOrder.ascending ? ">" : "<");
    var prefix = "aq_page_";

    var columnName =
        columnNameForProperty(pagingProperty, withTableNamespace: true);
    var variableName = columnNameForProperty(pagingProperty, withPrefix: prefix);

    return new QueryPredicate(
        "$columnName ${operator} @$variableName${typeSuffix(pagingProperty)}",
        {variableName: pageDescriptor.boundingValue});
  }

  // todo: this sucks
  List<PropertyToRowMapper> joinElementsFromQueryMatchable(
      QueryMatchableExtension matcherBackedObject) {
    var entity = matcherBackedObject.entity;
    var propertiesToJoin = matcherBackedObject.joinPropertyKeys;

    return propertiesToJoin.map((propertyName) {
      QueryMatchableExtension inner =
          matcherBackedObject.backingMap[propertyName];

      var relDesc = entity.relationships[propertyName];
      var predicate = predicateFromMatcherBackedObject(inner);
      var nestedProperties =
          nestedResultProperties[inner.entity.instanceType.reflectedType];
      var propertiesToFetch =
          nestedProperties ?? inner.entity.defaultProperties;

      var joinElement = new PropertyToRowMapper(
          PersistentJoinType.leftOuter,
          relDesc,
          predicate,
          mappersForKeys(
              inner.entity, propertiesToFetch));
      if (inner.hasJoinElements) {
        joinElement.orderedMappingElements
            .addAll(joinElementsFromQueryMatchable(inner));
      }

      return joinElement;
    }).toList();
  }

  // todo: this all sucks
  String joinStringForJoin(PropertyToRowMapper ji) {
    var parentEntity = ji.property.entity;
    var parentProperty = parentEntity.properties[parentEntity.primaryKey];
    var parentColumnName =
        columnNameForProperty(parentProperty, withTableNamespace: true);
    var childColumnName =
        columnNameForProperty(ji.joinProperty, withTableNamespace: true);

    var predicate =
        new QueryPredicate("$parentColumnName=$childColumnName", null);

    if (ji.predicate != null) {
      predicate = QueryPredicate.andPredicates([predicate, ji.predicate]);
    }

    return "${stringForJoinType(ji.type)} JOIN ${ji.joinProperty.entity.tableName} ON ${predicate.format}";
  }
}
