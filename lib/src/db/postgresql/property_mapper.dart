import 'package:postgres/postgres.dart';

import '../db.dart';
import '../query/matcher_internal.dart';
import 'entity_table.dart';

export 'property_column.dart';
export 'property_expression.dart';
export 'row_mapper.dart';

enum PersistentJoinType { leftOuter }

abstract class PostgresMapper {}

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

  PropertyMapper(this.table, this.property);

  ManagedPropertyDescription property;
  EntityTableMapper table;
  String get typeSuffix {
    var type =
        PostgreSQLFormat.dataTypeStringForDataType(typeMap[property.type]);
    if (type != null) {
      return ":$type";
    }

    return "";
  }

  String columnName(
      {bool withTypeSuffix: false,
      bool withTableNamespace: false,
      String withPrefix: null}) {
    var name = property.name;
    if (property is ManagedRelationshipDescription) {
      var relatedPrimaryKey = (property as ManagedRelationshipDescription)
          .destinationEntity
          .primaryKey;
      name = "${name}_$relatedPrimaryKey";
    }

    if (withTypeSuffix) {
      name = "$name$typeSuffix";
    }

    if (withTableNamespace) {
      return "${table.tableReference}.$name";
    } else if (withPrefix != null) {
      return "$withPrefix$name";
    }

    return name;
  }
}
