import 'dart:async';

import '../managed/object.dart';
import '../query/query.dart';
import 'postgresql_persistent_store.dart';
import 'postgresql_query.dart';
import 'query_builder.dart';

class PostgresQueryReduce<T extends ManagedObject>
    extends QueryReduceOperation<T> {
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
    return query.entity.identifyAttribute(selector).name;
  }

  Future<U> _execute<U>(String function) async {
    final builder = PostgresQueryBuilder(query);
    final buffer = StringBuffer();
    buffer.write("SELECT $function ");
    buffer.write("FROM ${builder.sqlTableName} ");

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    }

    final store = query.context.persistentStore as PostgreSQLPersistentStore;
    final connection = await store.executionContext;
    try {
      final result = await connection
          .query(buffer.toString(), substitutionValues: builder.variables)
          .timeout(Duration(seconds: query.timeoutInSeconds));
      return result.first.first as U;
    } on TimeoutException catch (e) {
      throw QueryException.transport("timed out connecting to database",
          underlyingException: e);
    }
  }
}
