import 'dart:mirrors';

import '../db.dart';
import 'property_mapper.dart';
import 'entity_table.dart';
import 'row_instantiator.dart';
import 'predicate_builder.dart';

abstract class PostgresMapper {}

class PostgresQueryBuilder extends Object with PredicateBuilder, RowInstantiator, EntityTableMapper {
  static const String valueKeyPrefix = "v_";

  PostgresQueryBuilder(this.entity,
      {List<String> returningProperties,
      Map<String, dynamic> values,
      ManagedObject whereBuilder,
      QueryPredicate predicate,
      List<RowMapper> nestedRowMappers,
      List<QuerySortDescriptor> sortDescriptors}) {

    returningOrderedMappers = returningProperties == null ? [] :
        PropertyToColumnMapper.fromKeys(this, entity, returningProperties);
    this.sortMappers = sortDescriptors
        ?.map((sd) => new PropertySortMapper(this, entity.properties[sd.key], sd.order))
        ?.toList();

    if (nestedRowMappers != null) {
      returningOrderedMappers.addAll(nestedRowMappers);
      nestedRowMappers.forEach((rm) {
        rm.parentTable = this;
      });
    }
    columnValues = values?.keys
        ?.map((key) => validatedColumnValueMapper(values, key))
        ?.where((v) => v != null)
        ?.toList() ?? [];


    if (containsJoins) {
      tableAlias = "t0";
    }

    var implicitJoins = <RowMapper>[];
    this.predicate = predicateFrom(whereBuilder, [predicate], implicitJoins);
    returningOrderedMappers.addAll(implicitJoins);
  }

  List<PropertyToColumnValue> columnValues;
  QueryPredicate predicate;
  List<PropertySortMapper> sortMappers;
  ManagedEntity entity;
  String tableAlias;

  String get primaryTableDefinition => tableDefinition;
  bool get containsJoins => returningOrderedMappers.reversed.any((p) => p is RowMapper);
  String get whereClause => predicate?.format;

  Map<String, dynamic> get substitutionValueMap {
    var m = <String, dynamic>{};
    if (predicate?.parameters != null) {
      m.addAll(this.predicate.parameters);
    }

    columnValues.forEach((PropertyToColumnValue c) {
      m[c.columnName(withPrefix: valueKeyPrefix)] = c.value;
    });

    returningOrderedMappers
        .where((rm) => rm is RowMapper)
        .forEach((rm) {
          m.addAll((rm as RowMapper).substitutionVariables);
        });

    return m;
  }

  List<PropertyToColumnMapper> get flattenedMappingElements {
    return returningOrderedMappers.expand((c) {
      if (c is RowMapper) {
        return c.flattened;
      }
      return [c];
    }).toList();
  }

  String get updateValueString {
    return columnValues.map((m) {
      var columnName = m.columnName();
      var variableName = m.columnName(withPrefix: "@$valueKeyPrefix", withTypeSuffix: true);
      return "$columnName=$variableName";
    }).join(",");
  }

  String get valuesColumnString {
    return columnValues.map((c) => c.columnName()).join(",");
  }

  String get insertionValueString {
    return columnValues
        .map((c) => c.columnName(withTypeSuffix: true, withPrefix: "@$valueKeyPrefix"))
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

  int aliasCounter = 0;
  String generateTableAlias() {
    tableAlias ??= "t0";
    aliasCounter ++;
    return "t$aliasCounter";
  }
}