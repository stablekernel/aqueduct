import 'dart:async';
import 'dart:mirrors';

import '../db.dart';
import '../query/mixin.dart';
import 'postgresql_mapping.dart';
import 'instantiator.dart';

class PostgresQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {
  PostgresQuery(this.context);

  ManagedContext context;

  bool get whereBuilderHasImplicitJoins {
    if (!hasWhereBuilder) {
      return false;
    }

    return where.backingMap.keys.any((key) {
      return whereBuilderHasImplicitJoinsForProperty(where, key);
    });
  }

  @override
  Future<InstanceType> insert() async {
    var rowMapper = new ManagedInstantiator(entity,
        returningProperties: propertiesToFetch,
        values: valueMap ?? values?.backingMap);

    var buffer = new StringBuffer();
    buffer.write("INSERT INTO ${rowMapper.tableDefinition} ");
    buffer.write("(${rowMapper.valuesColumnString}) ");
    buffer.write("VALUES (${rowMapper.insertionValueString}) ");

    if ((rowMapper.orderedMappingElements?.length ?? 0) > 0) {
      buffer.write("RETURNING ${rowMapper.returningColumnString}");
    }

    var results = await context.persistentStore
        .executeQuery(buffer.toString(), rowMapper.insertionValueMap, timeoutInSeconds);

    return rowMapper.instancesForRows(results).first;
  }

  @override
  Future<List<InstanceType>> update() async {
    var rowMapper = new ManagedInstantiator(entity,
        returningProperties: propertiesToFetch,
        values: valueMap ?? values?.backingMap,
        whereBuilder: (hasWhereBuilder ? where : null),
        predicate: predicate);

    var buffer = new StringBuffer();
    buffer.write("UPDATE ${rowMapper.tableDefinition} ");
    buffer.write("SET ${rowMapper.updateValueString} ");

    if (rowMapper.whereClause != null) {
      buffer.write("WHERE ${rowMapper.whereClause} ");
    } else if (!canModifyAllInstances) {
      throw new QueryException(QueryExceptionEvent.internalFailure,
          message:
          "Query would impact all records. This could be a destructive error. Set canModifyAllInstances on the Query to execute anyway.");
    }

    if ((rowMapper.orderedMappingElements?.length ?? 0) > 0) {
      buffer.write(
          "RETURNING ${rowMapper.returningColumnString}");
    }

    var results = await context.persistentStore
        .executeQuery(buffer.toString(), rowMapper.updateValueMap, timeoutInSeconds);

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
    var rowMapper = new ManagedInstantiator(entity,
        predicate: predicate,
        whereBuilder: hasWhereBuilder ? where : null);

    var buffer = new StringBuffer();
    buffer.write("DELETE FROM ${rowMapper.tableDefinition} ");
    if (rowMapper.whereClause != null) {
      buffer.write("WHERE ${rowMapper.whereClause} ");
    } else if (!canModifyAllInstances) {
      throw new QueryException(QueryExceptionEvent.internalFailure,
          message:
          "Query would impact all records. This could be a destructive error. Set canModifyAllInstances on the Query to execute anyway.");
    }

    return context.persistentStore.executeQuery(
        buffer.toString(), rowMapper.predicateValueMap, timeoutInSeconds,
        returnType: PersistentStoreQueryReturnType.rowCount);
  }

  @override
  Future<InstanceType> fetchOne() async {
    var rowMapper = createFetchMapper();

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
    return _fetch(createFetchMapper());
  }

  //////

  ManagedInstantiator createFetchMapper() {
    if (pageDescriptor != null) {
      validatePageDescriptor();
      if (pageDescriptor.boundingValue != null)
//      if (pageDescriptor?.boundingValue == null) {
//        return null;
//      }
//
//      var pagingProperty = entity.properties[pageDescriptor.propertyName];
//      var operator =
//      (pageDescriptor.order == QuerySortOrder.ascending ? ">" : "<");
//      var prefix = "aq_page_";
//
//      var columnName =
//      namer.columnNameForProperty(pagingProperty, withTableNamespace: true);
//      var variableName =
//      namer.columnNameForProperty(pagingProperty, withPrefix: prefix);
//
//      return new QueryPredicate(
//          "$columnName ${operator} @$variableName${namer.typeSuffixForProperty(pagingProperty)}",
//          {variableName: pageDescriptor.boundingValue});
    }

    var rowMapper = new ManagedInstantiator(entity)
      ..properties = propertiesToFetch
      ..addJoinElements(joinElementsFromQuery(this))
      ..queryPredicate = predicate
      ..queryPredicateObject = hasWhereBuilder ? where : null;

    // Have to also add pagingPredicate if it exists...

    if (rowMapper.containsJoins && pageDescriptor != null) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
          "Cannot use 'Query<T>' with both 'pageDescriptor' and joins currently.");
    }

    return rowMapper;
  }

  Future<List<InstanceType>> _fetch(ManagedInstantiator rowMapper) async {
    var namer = new PostgresNamer();

    var p = hasWhereBuilder ? predicateFromMatcherBackedObject(where, namer) : predicate;
    var allPredicates = QueryPredicate.andPredicates(
        [p, pagingPredicate(namer)].where((p) => p != null));

    var buffer = new StringBuffer();
    buffer.write("SELECT ${rowMapper.namespacedReturningColumnString} ");
    buffer.write("FROM ${rowMapper.tableDefinition} ");

    if (rowMapper.containsJoins) {
      buffer.write("${rowMapper.joinString} ");
    }

    if (rowMapper.whereClause != null) {
      buffer.write("WHERE ${rowMapper.whereClause} ");
    }

    buffer.write("${orderByString(namer)} ");

    if (fetchLimit != 0) {
      buffer.write("LIMIT ${fetchLimit} ");
    }

    if (offset != 0) {
      buffer.write("OFFSET ${offset} ");
    }

    var results = await context.persistentStore
        .executeQuery(buffer.toString(), rowMapper.predicateValueMap, timeoutInSeconds);

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
              "Property '${pageDescriptor.propertyName}' in pageDescriptor does not exist on '${entity.tableName}'.");
    }

    if (pageDescriptor.boundingValue != null &&
        !prop.isAssignableWith(pageDescriptor.boundingValue)) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
              "Property '${pageDescriptor.propertyName}' in pageDescriptor has invalid type (Expected: '${prop.type}' Got: ${pageDescriptor.boundingValue.runtimeType}').");
    }
  }

  String orderByString(PostgresNamer namer) {
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
      var columnName =
        namer.columnNameForProperty(property, withTableNamespace: true);
      var order = (sd.order == QuerySortOrder.ascending ? "ASC" : "DESC");

      return "$columnName $order";
    }).join(",");

    return "ORDER BY $joinedSortDescriptors";
  }

  QueryPredicate pagingPredicate(PostgresNamer namer) {
    validatePageDescriptor();

    if (pageDescriptor?.boundingValue == null) {
      return null;
    }

    var pagingProperty = entity.properties[pageDescriptor.propertyName];
    var operator =
        (pageDescriptor.order == QuerySortOrder.ascending ? ">" : "<");
    var prefix = "aq_page_";

    var columnName =
      namer.columnNameForProperty(pagingProperty, withTableNamespace: true);
    var variableName =
      namer.columnNameForProperty(pagingProperty, withPrefix: prefix);

    return new QueryPredicate(
        "$columnName ${operator} @$variableName${namer.typeSuffixForProperty(pagingProperty)}",
        {variableName: pageDescriptor.boundingValue});
  }

  List<PropertyToRowMapper> joinElementsFromQuery(PostgresQuery q) {
    var explicitJoins = q.subQueries?.keys?.map((relationshipDesc) {
          var subQuery = q.subQueries[relationshipDesc] as PostgresQuery;
          var joinElement = new PropertyToRowMapper(
              PersistentJoinType.leftOuter,
              relationshipDesc,
              PropertyToColumnMapper.fromKeys(subQuery.entity, subQuery.propertiesToFetch),
              explicitPredicate: subQuery.predicate,
              where: subQuery.hasWhereBuilder ? subQuery.where : null);

          joinElement.orderedMappingElements
              .addAll(joinElementsFromQuery(subQuery));

          return joinElement;
        })?.toList() ??
        [];

    if (q.hasWhereBuilder) {
      var implicitJoins = joinElementsFromMatcherBackedObject(q.where);
      for (var implicit in implicitJoins) {
        if (!explicitJoins.any(
            (explicit) => explicit.representsSameJoinAs(implicit))) {

          explicitJoins.add(implicit);
        }
      }
    }

    return explicitJoins;
  }

  List<PropertyToRowMapper> joinElementsFromMatcherBackedObject(
      ManagedObject object) {
    var whereRelationshipKeys = object.backingMap.keys.where((key) {
      return whereBuilderHasImplicitJoinsForProperty(object, key);
    });

    return whereRelationshipKeys.map((key) {
      var joinElement = new PropertyToRowMapper(PersistentJoinType.leftOuter,
          object.entity.relationships[key], []);

      var value = object.backingMap[key];
      if (value is ManagedSet) {
        joinElement.orderedMappingElements
            .addAll(joinElementsFromMatcherBackedObject(value.matchOn));
      } else {
        joinElement.orderedMappingElements
            .addAll(joinElementsFromMatcherBackedObject(value));
      }

      return joinElement;
    }).toList();
  }

  bool whereBuilderHasImplicitJoinsForProperty(ManagedObject object, String propertyName) {
    if (object.entity.relationships.containsKey(propertyName)) {
      var value = object.backingMap[propertyName];
      if (value is ManagedObject) {
        return value.backingMap.isNotEmpty;
      } else if (value is ManagedSet) {
        if (value.hasMatchOn) {
          return value.matchOn.backingMap.isNotEmpty;
        }

        return false;
      }
      return false;
    }

    return false;
  }

  // todo: this all sucks
  String joinStringForJoin(PropertyToRowMapper ji, QueryPredicate additionalPredicate, PostgresNamer namer) {
    var parentEntity = ji.property.entity;
    var parentProperty = parentEntity.properties[parentEntity.primaryKey];
    var parentColumnName =
    namer.columnNameForProperty(parentProperty, withTableNamespace: true);
    var childColumnName =
    namer.columnNameForProperty(ji.joinProperty, withTableNamespace: true);

    var predicate =
        new QueryPredicate("$parentColumnName=$childColumnName", null);

    if (additionalPredicate != null) {
      predicate = QueryPredicate.andPredicates([predicate, additionalPredicate]);
    }

    return "${namer.stringForJoinType(ji.type)} JOIN ${namer.tableDefinitionForEntity(ji.joinProperty.entity)} ON ${predicate.format}";
  }
}
