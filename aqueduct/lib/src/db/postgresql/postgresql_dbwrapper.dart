import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/property_description.dart';
import 'package:aqueduct/src/db/postgresql/builders/expression.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/shared/builders/expression.dart';
import 'package:aqueduct/src/db/shared/builders/table.dart';
import 'package:aqueduct/src/db/shared/returnable.dart';
import 'package:postgres/postgres.dart';

class PostgreSQLDbWrapper extends DbWrapper {
  factory PostgreSQLDbWrapper() => _singleton;
  PostgreSQLDbWrapper._internal();
  static PostgreSQLDbWrapper _singleton = PostgreSQLDbWrapper._internal();



  @override
  String suffix(ManagedPropertyDescription property) {
    var type =
        PostgreSQLFormat.dataTypeStringForDataType(typeMap[property.type.kind]);
    if (type != null) {
      return ":$type";
    }

    return "";
  }

  static Map<ManagedPropertyType, PostgreSQLDataType> typeMap = {
    ManagedPropertyType.integer: PostgreSQLDataType.integer,
    ManagedPropertyType.bigInteger: PostgreSQLDataType.bigInteger,
    ManagedPropertyType.string: PostgreSQLDataType.text,
    ManagedPropertyType.datetime: PostgreSQLDataType.timestampWithoutTimezone,
    ManagedPropertyType.boolean: PostgreSQLDataType.boolean,
    ManagedPropertyType.doublePrecision: PostgreSQLDataType.double,
    ManagedPropertyType.document: PostgreSQLDataType.json
  };

  @override
  ColumnExpressionBuilder getColumnExpressionBuilder(TableBuilder table,
      ManagedPropertyDescription property, PredicateExpression expression,
      {String prefix = ""}) {
    return PostgreSQLColumnExpressionBuilder(this, table, property, expression,
        prefix: prefix);
  }

  @override
  
  String get sqlName => "PostgreSQL";
}
