import 'dart:mirrors';

import '../db.dart';
import '../query/sort_descriptor.dart';
import 'entity_table.dart';
import 'predicate_builder.dart';
import 'property_mapper.dart';
import 'row_instantiator.dart';

class PostgresQueryBuilder extends Object
    with PredicateBuilder, RowInstantiator, EntityTableMapper {
  static const String valueKeyPrefix = "v_";

  PostgresQueryBuilder(this.entity,
      {List<String> returningProperties,
      Map<String, dynamic> values,
      ManagedObject whereBuilder,
      QueryPredicate predicate,
      List<RowMapper> nestedRowMappers,
      List<QuerySortDescriptor> sortDescriptors,
      bool aliasTables: false}) {
    if (aliasTables) {
      shouldAliasTables = true;
      tableAlias = "t0";
    }

    if (returningProperties == null) {
      returningOrderedMappers = [];
    } else {
      returningOrderedMappers =
          PropertyToColumnMapper.fromKeys(this, entity, returningProperties);
    }

    this.sortMappers = sortDescriptors
        ?.map((s) =>
            new PropertySortMapper(this, entity.properties[s.key], s.order))
        ?.toList();

    if (nestedRowMappers != null) {
      returningOrderedMappers.addAll(nestedRowMappers);
      nestedRowMappers.forEach((rm) {
        rm.originatingTable = this;

        // If we're joining on belongsTo relationship, ensure
        // that foreign key column gets ignored during instantiation.
        // It'll get populated by the joined table.
        returningOrderedMappers.where((m) {
          if (m is PropertyToColumnMapper) {
            return identical(m.property, rm.joiningProperty);
          }

          return false;
        }).forEach((m) {
          (m as PropertyToColumnMapper)
              .isForeignKeyColumnAndWillBePopulatedByJoin = true;
        });
      });
    }

    columnValueMappers = values?.keys
            ?.map((key) => validatedColumnValueMapper(values, key))
            ?.where((v) => v != null)
            ?.toList() ??
        [];

    var implicitJoins = <RowMapper>[];
    finalizedPredicate =
        predicateFrom(whereBuilder, [predicate], implicitJoins);
    returningOrderedMappers.addAll(implicitJoins);
  }

  bool shouldAliasTables = false;

  List<PropertyToColumnValue> columnValueMappers;
  QueryPredicate finalizedPredicate;
  List<PropertySortMapper> sortMappers;
  ManagedEntity entity;
  String tableAlias;

  EntityTableMapper get rootTableMapper => this;
  String get primaryTableDefinition => tableDefinition;
  bool get containsJoins =>
      returningOrderedMappers.reversed.any((p) => p is RowMapper);
  String get whereClause => finalizedPredicate?.format;

  Map<String, dynamic> get substitutionValueMap {
    var m = <String, dynamic>{};
    if (finalizedPredicate?.parameters != null) {
      m.addAll(finalizedPredicate.parameters);
    }

    columnValueMappers.forEach((PropertyToColumnValue c) {
      m[c.columnName(withPrefix: valueKeyPrefix)] = c.value;
    });

    returningOrderedMappers.where((rm) => rm is RowMapper).forEach((rm) {
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
    return columnValueMappers.map((m) {
      var columnName = m.columnName();
      var variableName =
          m.columnName(withPrefix: "@$valueKeyPrefix", withTypeSuffix: true);
      return "$columnName=$variableName";
    }).join(",");
  }

  String get valuesColumnString {
    return columnValueMappers.map((c) => c.columnName()).join(",");
  }

  String get insertionValueString {
    return columnValueMappers
        .map((c) =>
            c.columnName(withTypeSuffix: true, withPrefix: "@$valueKeyPrefix"))
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
        .map((p) => p.columnName(withTableNamespace: shouldAliasTables))
        .join(",");
  }

  String get orderByString {
    var allSortMappers = new List<PropertySortMapper>.from(sortMappers);

    var nestedSorts = returningOrderedMappers
        .where((m) => m is RowMapper)
        .expand((m) => (m as RowMapper).sortMappers ?? <PropertySortMapper>[]);
    allSortMappers.addAll(nestedSorts);

    if ((allSortMappers?.length ?? 0) == 0) {
      return "";
    }

    return "ORDER BY ${allSortMappers.map((s) => s.orderByString).join(",")}";
  }

  PropertyToColumnValue validatedColumnValueMapper(
      Map<String, dynamic> valueMap, String key) {
    var property = entity.properties[key];
    if (property == null) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
              "Property $key in values does not exist on ${entity.tableName}");
    }

    if (property is ManagedRelationshipDescription) {
      if (property.relationshipType != ManagedRelationshipType.belongsTo) {
        return null;
      }

      var value = valueMap[key];
      if (value != null) {
        if (value is ManagedObject || value is Map) {
          return new PropertyToColumnValue(
              this, property, value[property.destinationEntity.primaryKey]);
        }

        throw new QueryException(QueryExceptionEvent.internalFailure,
            message:
                "Property $key on ${entity.tableName} in 'Query.values' must be a 'Map' or ${MirrorSystem.getName(
                property.destinationEntity.instanceType.simpleName)} ");
      }
    }

    return new PropertyToColumnValue(this, property, valueMap[key]);
  }

  QueryPredicate predicateFrom(
      ManagedObject matcherObject,
      List<QueryPredicate> predicates,
      List<RowMapper> createdImplicitRowMappers) {
    var matchers =
        propertyExpressionsFromObject(matcherObject, createdImplicitRowMappers);
    var allPredicates = matchers.expand((p) => [p.predicate]).toList();
    allPredicates.addAll(predicates.where((p) => p != null));
    return QueryPredicate.andPredicates(allPredicates);
  }

  int aliasCounter = 0;
  String generateTableAlias() {
    tableAlias ??= "t0";
    aliasCounter++;
    return "t$aliasCounter";
  }
}
