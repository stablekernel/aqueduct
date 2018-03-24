import 'dart:async';

import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/postgresql/mappers/row.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';

import '../db.dart';
import '../query/mixin.dart';
import '../query/sort_descriptor.dart';
import 'package:aqueduct/src/db/postgresql/mappers/column.dart';
import 'query_builder.dart';
import 'postgresql_query_reduce.dart';

class PostgresQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {
  PostgresQuery(this.context);

  PostgresQuery.withEntity(this.context, ManagedEntity entity) {
    _entity = entity;
  }

  @override
  ManagedContext context;

  @override
  ManagedEntity get entity => _entity ?? context.dataModel.entityForType(InstanceType);

  ManagedEntity _entity;

  @override
  QueryReduceOperation<InstanceType> get reduce {
    return new PostgresQueryReduce(this);
  }

  @override
  Future<InstanceType> insert() async {
    validateInput(ValidateOperation.insert);

    var builder = new PostgresQueryBuilder(entity,
        returningProperties: propertiesToFetch, values: valueMap ?? values?.backing?.contents);

    var buffer = new StringBuffer();
    buffer.write("INSERT INTO ${builder.primaryTableDefinition} ");

    if (builder.columnValueMappers.isEmpty) {
      buffer.write("VALUES (DEFAULT) ");
    } else {
      buffer.write("(${builder.valuesColumnString}) ");
      buffer.write("VALUES (${builder.insertionValueString}) ");
    }

    if ((builder.orderedReturnMappers?.length ?? 0) > 0) {
      buffer.write("RETURNING ${builder.returningColumnString}");
    }

    var results =
        await context.persistentStore.executeQuery(buffer.toString(), builder.substitutionValueMap, timeoutInSeconds);

    return builder.instancesForRows(results).first;
  }

  @override
  Future<List<InstanceType>> update() async {
    validateInput(ValidateOperation.update);

    var builder = new PostgresQueryBuilder(entity,
        returningProperties: propertiesToFetch,
        values: valueMap ?? values?.backing?.contents,
        expressions: expressions,
        predicate: predicate);

    var buffer = new StringBuffer();
    buffer.write("UPDATE ${builder.primaryTableDefinition} ");
    buffer.write("SET ${builder.updateValueString} ");

    if (builder.whereClause != null) {
      buffer.write("WHERE ${builder.whereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }

    if ((builder.orderedReturnMappers?.length ?? 0) > 0) {
      buffer.write("RETURNING ${builder.returningColumnString}");
    }

    var results =
        await context.persistentStore.executeQuery(buffer.toString(), builder.substitutionValueMap, timeoutInSeconds);

    return builder.instancesForRows(results);
  }

  @override
  Future<InstanceType> updateOne() async {
    var results = await update();
    if (results.length == 1) {
      return results.first;
    } else if (results.length == 0) {
      return null;
    }

    throw new StateError("Query error. 'updateOne' modified more than one row in '${entity.tableName}'. "
            "This was likely unintended and may be indicativate of a more serious error. Query "
            "should add 'where' constraints on a unique column.");
  }

  @override
  Future<int> delete() async {
    var builder = new PostgresQueryBuilder(entity, predicate: predicate, expressions: expressions);

    var buffer = new StringBuffer();
    buffer.write("DELETE FROM ${builder.primaryTableDefinition} ");

    if (builder.whereClause != null) {
      buffer.write("WHERE ${builder.whereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }

    return context.persistentStore.executeQuery(buffer.toString(), builder.substitutionValueMap, timeoutInSeconds,
        returnType: PersistentStoreQueryReturnType.rowCount);
  }

  @override
  Future<InstanceType> fetchOne() async {
    var rowMapper = createFetchMapper();

    if (!rowMapper.containsJoins) {
      fetchLimit = 1;
    }

    var results = await _fetch(rowMapper);
    if (results.length == 1) {
      return results.first;
    } else if (results.length > 1) {
      throw new StateError("Query error. 'fetchOne' returned more than one row from '${entity.tableName}'. "
          "This was likely unintended and may be indicativate of a more serious error. Query "
          "should add 'where' constraints on a unique column.");
    }

    return null;
  }

  @override
  Future<List<InstanceType>> fetch() async {
    return _fetch(createFetchMapper());
  }

  //////

  PostgresQueryBuilder createFetchMapper() {
    var allSortDescriptors = new List<QuerySortDescriptor>.from(sortDescriptors ?? []);

    // Add a sort descriptor and potentially another expression
    if (pageDescriptor != null) {
      validatePageDescriptor();
      var pageSortDescriptor = new QuerySortDescriptor(pageDescriptor.propertyName, pageDescriptor.order);
      allSortDescriptors.insert(0, pageSortDescriptor);

      if (pageDescriptor.boundingValue != null) {
        final prop = entity.properties[pageDescriptor.propertyName];
        final operator = pageDescriptor.order == QuerySortOrder.ascending ? PredicateOperator.greaterThan : PredicateOperator.lessThan;
        final expr = new QueryExpression(new KeyPath(prop),
            withExpressions: [new ComparisonExpression(pageDescriptor.boundingValue, operator)]);

        expressions.add(expr);
      }
    }

    var builder = new PostgresQueryBuilder(entity,
        returningProperties: propertiesToFetch,
        predicate: predicate,
        expressions: expressions,
        joinedRowMappers: rowMappersFromSubqueries,
        sortDescriptors: allSortDescriptors,
        aliasTables: true);

    if (builder.containsJoins && pageDescriptor != null) {
      throw new StateError("Invalid query. Cannot set both 'pageDescription' and use 'join' in query.");
    }

    return builder;
  }

  Future<List<InstanceType>> _fetch(PostgresQueryBuilder builder) async {
    var buffer = new StringBuffer();
    buffer.write("SELECT ${builder.returningColumnString} ");
    buffer.write("FROM ${builder.primaryTableDefinition} ");

    if (builder.containsJoins) {
      buffer.write("${builder.joinString} ");
    }

    if (builder.whereClause != null) {
      buffer.write("WHERE ${builder.whereClause} ");
    }

    buffer.write("${builder.orderByString} ");

    if (fetchLimit != 0) {
      buffer.write("LIMIT $fetchLimit ");
    }

    if (offset != 0) {
      buffer.write("OFFSET $offset ");
    }

    var results =
        await context.persistentStore.executeQuery(buffer.toString(), builder.substitutionValueMap, timeoutInSeconds);

    return builder.instancesForRows(results);
  }

  void validatePageDescriptor() {
    var prop = entity.attributes[pageDescriptor.propertyName];
    if (prop == null) {
      throw new StateError("Invalid query page descriptor. Column '${pageDescriptor.propertyName}' does not exist for table '${entity.tableName}'");
    }

    if (pageDescriptor.boundingValue != null && !prop.isAssignableWith(pageDescriptor.boundingValue)) {
      throw new StateError("Invalid query page descriptor. Bounding value for column '${pageDescriptor.propertyName}' has invalid type.");
    }
  }

  List<RowMapper> get rowMappersFromSubqueries {
    return subQueries?.keys?.map((relationshipDesc) {
          var subQuery = subQueries[relationshipDesc] as PostgresQuery;
          var joinElement = new RowMapper(PersistentJoinType.leftOuter, relationshipDesc, subQuery.propertiesToFetch,
              predicate: subQuery.predicate,
              sortDescriptors: subQuery.sortDescriptors,
              expressions: subQuery.expressions);
          joinElement.addRowMappers(subQuery.rowMappersFromSubqueries);

          return joinElement;
        })?.toList() ??
        [];
  }

  static final StateError canModifyAllInstancesError = new StateError(
      "Invalid Query<T>. Query is either update or delete query with no WHERE clause. To confirm this query is correct, set 'canModifyAllInstances' to true.");
}
