import 'package:postgres/postgres.dart';
import '../db.dart';

import 'property_expression.dart';

export 'property_expression.dart';
export 'property_column.dart';
export 'property_row.dart';

enum PersistentJoinType { leftOuter }

abstract class PropertyMapper {
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

  PropertyMapper(this.property);

  String get name;
  ManagedPropertyDescription property;
  String tableAlias;

  String columnName({bool withTypeSuffix: false, bool withTableNamespace: false, String withPrefix: null}) {
    var name = property.name;
    if (property is ManagedRelationshipDescription) {
      name = "${name}_${(property as ManagedRelationshipDescription).destinationEntity.primaryKey}";
    }

    if (withTypeSuffix) {
      name = "$name${typeSuffixForProperty(property)}";
    }

    if (withTableNamespace) {
      var resolvedTableName = tableAlias ?? property.entity.tableName;
      return "$resolvedTableName.$name";
    } else if (withPrefix != null) {
      return "$withPrefix$name";
    }

    return name;
  }
}

abstract class PredicateBuilder {
  ManagedEntity get entity;

  QueryPredicate predicateFrom(ManagedObject matcherObject, List<QueryPredicate> predicates) {
    var matchers = propertyExpressionsFromObject(matcherObject);
    var allPredicates = matchers.expand((p) => [p.predicate]).toList();
    allPredicates.addAll(predicates.where((p) => p != null));
    return QueryPredicate.andPredicates(allPredicates);
  }

  List<PropertyExpression> propertyExpressionsFromObject(ManagedObject obj) {
    if (obj == null) {
      return [];
    }

    var entity = obj.entity;
    return obj.backingMap.keys.where((propertyName) {
      var desc = entity.properties[propertyName];
      if (desc is ManagedRelationshipDescription) {
        return desc.relationshipType == ManagedRelationshipType.belongsTo;
      }

      return true;
    })
    .map((propertyName) {
      return new PropertyExpression(entity.properties[propertyName], obj.backingMap[propertyName]);
    })
    .toList();

//    var relationshipPredicates = obj.backingMap.keys.where((propertyName) {
//      var desc = entity.properties[propertyName];
//      if (desc is ManagedRelationshipDescription) {
//        return desc.relationshipType != ManagedRelationshipType.belongsTo;
//      }
//
//      return false;
//    }).map((propertyName) {
//      var innerObject = obj.backingMap[propertyName];
//      if (innerObject is ManagedSet) {
//        return predicateFromMatcherBackedObject(innerObject.matchOn);
//      }
//      return predicateFromMatcherBackedObject(innerObject);
//    }).toList();
//
//    if (relationshipPredicates.isEmpty) {
//      return predicate;
//    }
//
//    var total = [predicate];
//    total.addAll(relationshipPredicates);
//
//    return QueryPredicate.andPredicates(total.where((q) => q != null).toList());
  }}
