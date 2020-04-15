import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:sqljocky5/sqljocky.dart';
import 'mysql_persistent_store.dart';
import 'mysql_query.dart';
import 'mysql_query_builder.dart';
import 'utils.dart';

class MySqlQueryReduce<T extends ManagedObject>
    extends QueryReduceOperation<T> {
  MySqlQueryReduce(this.query);

  final MySqlQuery<T> query;

  @override
  Future<double> average(num selector(T object)) {
    return _execute("avg(${_columnName(selector)})");
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
    final builder = MySqlQueryBuilder(query);
    final buffer = StringBuffer();
    buffer.write("SELECT $function ");
    buffer.write("FROM ${builder.sqlTableName} ");

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    }
    final store = query.context.persistentStore as MySqlPersistentStore;
    final connection = await store.executionContext;
    try {
      String sql = buffer.toString();
      print(sql);
      List<dynamic> params =
          MySqlUtils.getMySqlVariables(sql, builder.variables);
      StreamedResults result;
      if (params == null || params.isEmpty) {
        result = await connection
            .execute(sql)
            .timeout(Duration(seconds: query.timeoutInSeconds));
      } else {
        result = await connection
            .prepared(sql, params)
            .timeout(Duration(seconds: query.timeoutInSeconds));
      
      }
      dynamic val=(await result.first).first;
      if(U.toString() ==val.runtimeType.toString()){
        return val as U;
      }
      if(U.toString()=="int"){
        return val.toInt() as U;
      }
      return  val.toDouble() as U;
    } on TimeoutException catch (e) {
      throw QueryException.transport("timed out connecting to database",
          underlyingException: e);
    }
  }
}
