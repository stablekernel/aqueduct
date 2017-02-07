import 'dart:mirrors';

import 'package:postgres/postgres.dart';

import '../db.dart';
import 'property_mapper.dart';
import 'entity_table.dart';
import 'row_instantiator.dart';

abstract class PostgresMapper {}

class PostgresQueryBuilder extends Object with PredicateBuilder, RowInstantiator, EntityTableMapper {
  static const String valueKeyPrefixWhenUsingPredicate = "u_";

  PostgresQueryBuilder(this.entity,
      {List<String> returningProperties,
      Map<String, dynamic> values,
      ManagedObject whereBuilder,
      QueryPredicate predicate,
      List<RowMapper> nestedRowMappers,
      List<QuerySortDescriptor> sortDescriptors}) {

    this.properties = returningProperties;
    this.sortMappers = sortDescriptors
        ?.map((sd) => new PropertySortMapper(this, entity.properties[sd.key], sd.order))
        ?.toList();
    substitutionValueMap = <String, dynamic>{};

    if (nestedRowMappers != null) {
      returningOrderedMappers.addAll(nestedRowMappers);
      nestedRowMappers.forEach((rm) {
        rm.parentTable = this;
      });
    }

    this.predicate = predicateFrom(whereBuilder, [predicate]);

    if (this.predicate?.parameters != null) {
      substitutionValueMap.addAll(this.predicate.parameters);
    }

    this.values = values;
    var valueKeyMapper = (PropertyToColumnValue c) {
      substitutionValueMap[c.columnName()] = c.value;
    };
    if (this.predicate != null) {
      valueKeyMapper = (PropertyToColumnValue c) {
        substitutionValueMap[c.columnName(withPrefix: valueKeyPrefixWhenUsingPredicate)] = c.value;
      };
    }
    columnValues.forEach(valueKeyMapper);

    nestedRowMappers?.forEach((rm) {
      substitutionValueMap.addAll(rm.substitutionVariables);
    });
  }

  List<PropertyToColumnValue> columnValues;
  QueryPredicate predicate;
  List<PropertySortMapper> sortMappers;
  Map<String, dynamic> substitutionValueMap;
  ManagedEntity entity;

  List<PropertyToColumnMapper> get flattenedMappingElements {
    return returningOrderedMappers.expand((c) {
      if (c is RowMapper) {
        return c.flattened;
      }
      return [c];
    }).toList();
  }

  String get primaryTableDefinition => tableDefinition;

  // todo: optimize this
  bool get containsJoins {
    return returningOrderedMappers.reversed.any((m) => m is RowMapper);
  }

  String get whereClause {
    return predicate?.format;
  }

  String get updateValueString {
    var prefix = "@$valueKeyPrefixWhenUsingPredicate";
    if (this.predicate == null) {
      prefix = "@";
    }
    return columnValues.map((m) {
      var columnName = m.columnName();
      var variableName = m.columnName(withPrefix: prefix, withTypeSuffix: true);
      return "$columnName=$variableName";
    }).join(",");
  }

  String get valuesColumnString {
    return columnValues.map((c) => c.columnName()).join(",");
  }

  String get insertionValueString {
    return columnValues
        .map((c) => c.columnName(withTypeSuffix: true, withPrefix: "@"))
        .join(",");
  }

  String get joinString {
    return returningOrderedMappers
        .where((e) => e is RowMapper)
        .map((e) => (e as RowMapper).joinString)
        .join(" ");
  }

  String get returningColumnString {
    return flattenedMappingElements
        .map((p) => p.columnName(withTableNamespace: containsJoins))
        .join(",");
  }

  String get orderByString {
    if ((sortMappers?.length ?? 0) == 0) {
      return "";
    }

    return "ORDER BY ${sortMappers.map((s) => s.orderByString).join(",")}";
  }

  void set properties(List<String> props) {
    if (props != null) {
      returningOrderedMappers =
          PropertyToColumnMapper.fromKeys(this, entity, props);
    } else {
      returningOrderedMappers = null;
    }
  }

  void set values(Map<String, dynamic> valueMap) {
    if (valueMap == null) {
      columnValues = [];
      return;
    }

    columnValues = valueMap.keys
        .map((key) => validatedColumnValueMapper(valueMap, key))
        .where((v) => v != null)
        .toList();
  }

  PropertyToColumnValue validatedColumnValueMapper(Map<String, dynamic> valueMap, String key) {
    var value = valueMap[key];
    var property = entity.properties[key];
    if (property == null) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
          "Property $key in values does not exist on ${entity.tableName}");
    }

    if (property is ManagedRelationshipDescription) {
      if (property.relationshipType !=
          ManagedRelationshipType.belongsTo) {
        return null;
      }

      if (value != null) {
        if (value is ManagedObject) {
          value = value[property.destinationEntity.primaryKey];
        } else if (value is Map) {
          value = value[property.destinationEntity.primaryKey];
        } else {
          throw new QueryException(QueryExceptionEvent.internalFailure,
              message:
              "Property $key on ${entity.tableName} in 'Query.values' must be a 'Map' or ${MirrorSystem.getName(
                  property.destinationEntity.instanceType.simpleName)} ");
        }
      }
    }

    return new PropertyToColumnValue(this, property, value);
  }
}