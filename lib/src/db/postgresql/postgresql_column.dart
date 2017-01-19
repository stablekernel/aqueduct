import 'package:postgres/postgres.dart';
import '../db.dart';

Map<MatcherOperator, String> symbolTable = {
  MatcherOperator.lessThan: "<",
  MatcherOperator.greaterThan: ">",
  MatcherOperator.notEqual: "!=",
  MatcherOperator.lessThanEqualTo: "<=",
  MatcherOperator.greaterThanEqualTo: ">=",
  MatcherOperator.equalTo: "="
};

Map<ManagedPropertyType, PostgreSQLDataType> typeMap = {
  ManagedPropertyType.integer: PostgreSQLDataType.integer,
  ManagedPropertyType.bigInteger: PostgreSQLDataType.bigInteger,
  ManagedPropertyType.string: PostgreSQLDataType.text,
  ManagedPropertyType.datetime: PostgreSQLDataType.timestampWithoutTimezone,
  ManagedPropertyType.boolean: PostgreSQLDataType.boolean,
  ManagedPropertyType.doublePrecision: PostgreSQLDataType.double
};

String typeSuffix(ManagedPropertyDescription desc) {
  var type = PostgreSQLFormat.dataTypeStringForDataType(typeMap[desc.type]);
  if (type != null) {
    return ":$type";
  }

  return "";
}

String columnNameForProperty(ManagedPropertyDescription desc,
    {bool typed: false, bool includeTableName: false, String prefix: null}) {
  var name = desc.name;
  if (desc is ManagedRelationshipDescription) {
    name = "${name}_${desc.destinationEntity.primaryKey}";
  }

  if (typed) {
    name = "$name${typeSuffix(desc)}";
  }

  if (includeTableName) {
    return "${desc.entity.tableName}.$name";
  }

  if (prefix != null) {
    name = "$prefix$name";
  }

  return name;
}

String columnListString(Iterable<ManagedPropertyDescription> columnMappings,
    {bool typed: false, bool includeTableName: false, String prefix: null}) {
  return columnMappings
      .map((c) =>
      columnNameForProperty(c, typed: typed,
          includeTableName: includeTableName,
          prefix: prefix))
      .join(",");
}