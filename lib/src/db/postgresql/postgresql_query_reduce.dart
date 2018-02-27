import 'dart:async';

import 'package:aqueduct/src/db/managed/backing.dart';
import 'package:aqueduct/src/db/query/mixin.dart';

import '../query/query.dart';
import '../managed/object.dart';
import 'postgresql_query.dart';
import 'postgresql_persistent_store.dart';
import 'query_builder.dart';

class PostgresQueryReduce<T extends ManagedObject> extends QueryReduceOperation<T>{
  PostgresQueryReduce(this.query);

  final PostgresQuery<T> query;

  @override
  Future<double> average(num selector(T object)) {
    return _execute("avg(${_columnName(selector)})::float");
  }

  @override
  Future<int> count() {
    return _execute("count(*)");
  }

  @override
  Future<U> maximum<U>(U selector(T object)) {
    return _execute("max(${_columnName(selector)})");
  }

  @override
  Future<U> minimum<U>(U selector(T object)) {
    return _execute("min(${_columnName(selector)})");
  }

  @override
  Future<U> sum<U extends num>(U selector(T object)) {
    return _execute("sum(${_columnName(selector)})");
  }

  String _columnName(dynamic selector(T object)) {
    return QueryMixin.identifyAttribute(query.entity, selector).name;
  }

  Future<U> _execute<U>(String function) async {
    var builder = new PostgresQueryBuilder(query.entity,
        predicate: query.predicate,
        whereBuilder: query.hasWhereBuilder ? query.where : null);
    var buffer = new StringBuffer();
    buffer.write("SELECT $function ");
    buffer.write("FROM ${builder.primaryTableDefinition} ");

    if (builder.whereClause != null) {
      buffer.write("WHERE ${builder.whereClause} ");
    }

    PostgreSQLPersistentStore store = query.context.persistentStore;
    var connection = await store.getDatabaseConnection();
    try {
      var result = await connection
          .query(buffer.toString(), substitutionValues: builder.substitutionValueMap)
          .timeout(new Duration(seconds: query.timeoutInSeconds));
      return result.first.first;
    } on TimeoutException catch (e) {
      throw new QueryException.transport("timed out connecting to database", underlyingException: e);
    }
  }
}