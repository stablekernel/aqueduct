import 'package:postgres/postgres.dart';
import '../db.dart';

import 'entity_table.dart';
import 'query_builder.dart';
export 'property_expression.dart';
export 'property_column.dart';
export 'property_row.dart';

enum PersistentJoinType { leftOuter }

abstract class PropertyMapper extends PostgresMapper {
  static Map<ManagedPropertyType, PostgreSQLDataType> typeMap = {
    ManagedPropertyType.integer: PostgreSQLDataType.integer,
    ManagedPropertyType.bigInteger: PostgreSQLDataType.bigInteger,
    ManagedPropertyType.string: PostgreSQLDataType.text,
    ManagedPropertyType.datetime: PostgreSQLDataType.timestampWithoutTimezone,
    ManagedPropertyType.boolean: PostgreSQLDataType.boolean,
    ManagedPropertyType.doublePrecision: PostgreSQLDataType.double
  };

  static Map<MatcherOperator, String> symbolTable = {
    MatcherOperator.lessThan: "<",
    MatcherOperator.greaterThan: ">",
    MatcherOperator.notEqual: "!=",
    MatcherOperator.lessThanEqualTo: "<=",
    MatcherOperator.greaterThanEqualTo: ">=",
    MatcherOperator.equalTo: "="
  };

  static String typeSuffixForProperty(ManagedPropertyDescription desc) {
    var type = PostgreSQLFormat.dataTypeStringForDataType(typeMap[desc.type]);
    if (type != null) {
      return ":$type";
    }

    return "";
  }

  PropertyMapper(this.table, this.property);

  ManagedPropertyDescription property;
  EntityTableMapper table;

  String columnName({bool withTypeSuffix: false, bool withTableNamespace: false, String withPrefix: null}) {
    var name = property.name;
    if (property is ManagedRelationshipDescription) {
      name = "${name}_${(property as ManagedRelationshipDescription).destinationEntity.primaryKey}";
    }

    if (withTypeSuffix) {
      name = "$name${typeSuffixForProperty(property)}";
    }

    if (withTableNamespace) {
      return "${table.tableReference}.$name";
    } else if (withPrefix != null) {
      return "$withPrefix$name";
    }

    return name;
  }
}

