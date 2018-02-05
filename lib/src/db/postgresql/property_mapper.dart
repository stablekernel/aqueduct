import 'dart:convert';

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
    ManagedPropertyType.doublePrecision: PostgreSQLDataType.double,
    ManagedPropertyType.document: PostgreSQLDataType.json
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

  final ManagedPropertyDescription property;
  final EntityTableMapper table;

  String get typeSuffix {
    var type = PostgreSQLFormat.dataTypeStringForDataType(typeMap[property.type.kind]);
    if (type != null) {
      return ":$type";
    }

    return "";
  }

  dynamic convertValueForStorage(dynamic value) {
    if (property is ManagedAttributeDescription) {
      if ((property as ManagedAttributeDescription).isEnumeratedValue) {
        return property.convertToPrimitiveValue(value);
      } else if ((property as ManagedAttributeDescription).type.kind == ManagedPropertyType.document) {
        return JSON.encode((value as Document).data);
      }
    }

    return value;
  }

  dynamic convertValueFromStorage(dynamic value) {
    if (property is ManagedAttributeDescription) {
      if ((property as ManagedAttributeDescription).isEnumeratedValue) {
        return property.convertFromPrimitiveValue(value);
      } else if ((property as ManagedAttributeDescription).type.kind == ManagedPropertyType.document) {
        return new Document.from(JSON.decode(value));
      }
    }

    return value;
  }

  String columnName({bool withTypeSuffix: false, bool withTableNamespace: false, String withPrefix}) {
    var name = property.name;
    if (property is ManagedRelationshipDescription) {
      var relatedPrimaryKey = (property as ManagedRelationshipDescription).destinationEntity.primaryKey;
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
