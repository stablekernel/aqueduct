import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/query/mixin.dart';
import 'package:sqljocky5/sqljocky.dart';
import 'mysql_query_builder.dart';
import 'mysql_query_reduce.dart';

class MySqlQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {
  MySqlQuery(this.context);

  MySqlQuery.withEntity(this.context, ManagedEntity entity) {
    _entity = entity;
  }

  @override
  ManagedContext context;

  @override
  Future<int> delete() async {
    var builder = MySqlQueryBuilder(this);

    var buffer = StringBuffer();
    buffer.write("DELETE FROM ${builder.sqlTableName} ");

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }

    final StreamedResults result = await context.persistentStore.executeQuery(
        buffer.toString(), builder.variables, timeoutInSeconds,
        returnType: PersistentStoreQueryReturnType.rowCount) as StreamedResults;
    return result.affectedRows;
  }

  @override
  ManagedEntity get entity =>
      _entity ?? context.dataModel.entityForType(InstanceType);

  ManagedEntity _entity;
  @override
  QueryReduceOperation<InstanceType> get reduce => MySqlQueryReduce(this);
  @override
  Future<List<InstanceType>> fetch() async {
    return _fetch(createFetchBuilder());
  }

  @override
  Future<InstanceType> fetchOne() async {
    var builder = createFetchBuilder();

    if (!builder.containsJoins) {
      fetchLimit = 1;
    }

    var results = await _fetch(builder);

    if (results.length == 1) {
      return results.first;
    } else if (results.length > 1) {
      throw StateError(
          "Query error. 'fetchOne' returned more than one row from '${entity.tableName}'. "
          "This was likely unintended and may be indicativate of a more serious error. Query "
          "should add 'where' constraints on a unique column.");
    }

    return null;
  }

  @override
  Future<InstanceType> insert() async {
    validateInput(Validating.insert);

    var builder = MySqlQueryBuilder(this);

    var buffer = StringBuffer();
    buffer.write("INSERT INTO ${builder.sqlTableName} ");

    if (builder.columnValueBuilders.isEmpty) {
      buffer.write("VALUES (DEFAULT) ");
    } else {
      buffer.write("(${builder.sqlColumnsToInsert}) ");
      buffer.write("VALUES (${builder.sqlValuesToInsert}); ");
    }
    StreamedResults results = await context.persistentStore
        .executeQuery(buffer.toString(), builder.variables, timeoutInSeconds) as StreamedResults;

    if (results.insertId > 0 && (builder.returning?.length ?? 0) > 0) {
      String sql =
          "SELECT ${builder.sqlColumnsToReturn} FROM ${builder.sqlTableName} WHERE `${builder.entity.primaryKey}`=${results.insertId}";
      final StreamedResults res = await context.persistentStore
          .executeQuery(sql, null, timeoutInSeconds) as StreamedResults;
      return builder.instancesForRows<InstanceType>(await res.toList()).first;
    }
    return null; //TODO:
    // return builder.instancesForRows<InstanceType>(results).first;
  }

  @override
  Future<List<InstanceType>> update() async {
    validateInput(Validating.update);

    var builder = MySqlQueryBuilder(this);

    var buffer = StringBuffer();
    buffer.write("UPDATE ${builder.sqlTableName} ");
    buffer.write("SET ${builder.sqlColumnsAndValuesToUpdate} ");

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ;");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }

    // if ((builder.returning?.length ?? 0) > 0) {
    //   // buffer.write("RETURNING ${builder.sqlColumnsToReturn}");
    // }
    
    final StreamedResults results = await context.persistentStore
        .executeQuery(buffer.toString(), builder.variables, timeoutInSeconds) as StreamedResults;
    if (results.affectedRows > 0 && (builder.returning?.length ?? 0) > 0) {
    
      String sql =
          "SELECT ${builder.sqlColumnsToReturn} FROM ${builder.sqlTableName} WHERE ${builder.sqlWhereClause} ";
      final StreamedResults res = await context.persistentStore
          .executeQuery(sql, builder.variables, timeoutInSeconds) as StreamedResults;
      return builder.instancesForRows(await res.toList());
    }
    // return builder.instancesForRows(results);
    return null;
  }

  @override
  Future<InstanceType> updateOne() async {
    var results = await update();
    if(results==null || results.isEmpty){
      return null;
    }else if(results.length==1){
      return results.first;
    }

    throw StateError(
        "Query error. 'updateOne' modified more than one row in '${entity.tableName}'. "
        "This was likely unintended and may be indicativate of a more serious error. Query "
        "should add 'where' constraints on a unique column.");
  }

  MySqlQueryBuilder createFetchBuilder() {
    var builder = MySqlQueryBuilder(this);

    if (pageDescriptor != null) {
      validatePageDescriptor();
    }

    if (builder.containsJoins && pageDescriptor != null) {
      throw StateError(
          "Invalid query. Cannot set both 'pageDescription' and use 'join' in query.");
    }

    return builder;
  }

  Future<List<InstanceType>> _fetch(MySqlQueryBuilder builder) async {
    var buffer = StringBuffer();
    buffer.write("SELECT ${builder.sqlColumnsToReturn} ");
    buffer.write("FROM ${builder.sqlTableName} ");

    if (builder.containsJoins) {
      buffer.write("${builder.sqlJoin} ");
    }

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    }

    buffer.write("${builder.sqlOrderBy} ");

    if (fetchLimit != 0) {
      buffer.write("LIMIT $fetchLimit ");
    }

    if (offset != 0) {
      buffer.write("OFFSET $offset ");
    }
    final StreamedResults results = await context.persistentStore
        .executeQuery(buffer.toString(), builder.variables, timeoutInSeconds) as StreamedResults;

    return builder.instancesForRows(await results.toList());
  }

  void validatePageDescriptor() {
    var prop = entity.attributes[pageDescriptor.propertyName];
    if (prop == null) {
      throw StateError(
          "Invalid query page descriptor. Column '${pageDescriptor.propertyName}' does not exist for table '${entity.tableName}'");
    }

    if (pageDescriptor.boundingValue != null &&
        !prop.isAssignableWith(pageDescriptor.boundingValue)) {
      throw StateError(
          "Invalid query page descriptor. Bounding value for column '${pageDescriptor.propertyName}' has invalid type.");
    }
  }

  static final StateError canModifyAllInstancesError = StateError(
      "Invalid Query<T>. Query is either update or delete query with no WHERE clause. To confirm this query is correct, set 'canModifyAllInstances' to true.");
}
