import 'package:postgres/postgres.dart';
import '../db.dart';

import 'property_expression.dart';
import 'entity_table.dart';
import 'query_builder.dart';
import 'property_row.dart';
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

abstract class PredicateBuilder implements EntityTableMapper {
  ManagedEntity get entity;

  QueryPredicate predicateFrom(ManagedObject matcherObject, List<QueryPredicate> predicates, List<RowMapper> createdImplicitRowMappers) {
    var matchers = propertyExpressionsFromObject(matcherObject, createdImplicitRowMappers);
    var allPredicates = matchers.expand((p) => [p.predicate]).toList();
    allPredicates.addAll(predicates.where((p) => p != null));
    return QueryPredicate.andPredicates(allPredicates);
  }

  List<PropertyExpression> propertyExpressionsFromObject(
      ManagedObject obj, List<RowMapper> createdImplicitRowMappers) {
    if (obj == null) {
      return [];
    }

    return obj.backingMap.keys.map((propertyName) {
      var desc = obj.entity.properties[propertyName];
      if (desc is ManagedRelationshipDescription) {
        if (desc.relationshipType == ManagedRelationshipType.belongsTo) {
          return [new PropertyExpression(this, obj.entity.properties[propertyName], obj.backingMap[propertyName])];
        }

        // Otherwise, this is an implicit join...
        // Do we have an existing guy?
        RowMapper innerRowMapper = returningOrderedMappers
            .where((m) => m is RowMapper)
            .firstWhere((m) => (m as RowMapper).representsRelationship(desc),
              orElse: () => null);
        if (innerRowMapper == null) {
          innerRowMapper = new RowMapper.implicit(PersistentJoinType.leftOuter, desc);
          innerRowMapper.parentTable = this;
          createdImplicitRowMappers.add(innerRowMapper);
        }

        var innerMatcher = obj.backingMap[propertyName];
        if (innerMatcher is ManagedSet) {
          return innerRowMapper.propertyExpressionsFromObject(innerMatcher.matchOn, createdImplicitRowMappers);
        }

        return innerRowMapper.propertyExpressionsFromObject(innerMatcher, createdImplicitRowMappers);
      }

      return [new PropertyExpression(this, obj.entity.properties[propertyName], obj.backingMap[propertyName])];
    })
    .expand((expressions) => expressions)
    .toList();
  }
}