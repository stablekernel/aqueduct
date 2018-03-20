import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/postgresql/mappers/column.dart';
import 'package:aqueduct/src/db/postgresql/mappers/row.dart';
import 'package:aqueduct/src/db/postgresql/mappers/table.dart';

import '../db.dart';
import '../query/sort_descriptor.dart';
import 'predicate_builder.dart';
import 'row_instantiator.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

class PostgresQueryBuilder extends Object with PredicateBuilder, RowInstantiator, EntityTableMapper {
  static const String valueKeyPrefix = "v_";

  PostgresQueryBuilder(this.entity,
      {List<KeyPath> returningProperties,
      Map<String, dynamic> values,
      List<QueryExpression<dynamic, dynamic>> expressions,
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
      returningOrderedMappers = ColumnMapper.fromKeys(this, entity, returningProperties);
    }

    this.sortMappers = sortDescriptors?.map((s) => new SortMapper(this, entity.properties[s.key], s.order))?.toList();

    if (nestedRowMappers != null) {
      returningOrderedMappers.addAll(nestedRowMappers);
      nestedRowMappers.forEach((rm) {
        rm.originatingTable = this;

        // If we're joining on belongsTo relationship, ensure
        // that foreign key column gets ignored during instantiation.
        // It'll get populated by the joined table.
        returningOrderedMappers.where((m) {
          if (m is ColumnMapper) {
            return identical(m.property, rm.joiningProperty);
          }

          return false;
        }).forEach((m) {
          (m as ColumnMapper).fetchAsForeignKey = true;
        });
      });
    }

    columnValueMappers =
        values?.keys?.map((key) => validatedColumnValueMapper(values, key))?.where((v) => v != null)?.toList() ?? [];

    var implicitJoins = <RowMapper>[];
    finalizedPredicate = predicateFrom(expressions, [predicate], implicitJoins);
    returningOrderedMappers.addAll(implicitJoins);
  }

  bool shouldAliasTables = false;

  List<PropertyValueMapper> columnValueMappers;
  QueryPredicate finalizedPredicate;
  List<SortMapper> sortMappers;

  @override
  ManagedEntity entity;

  @override
  String tableAlias;

  @override
  EntityTableMapper get rootTableMapper => this;

  String get primaryTableDefinition => tableDefinition;

  bool get containsJoins => returningOrderedMappers.reversed.any((p) => p is RowMapper);

  String get whereClause => finalizedPredicate?.format;

  Map<String, dynamic> get substitutionValueMap {
    var m = <String, dynamic>{};
    if (finalizedPredicate?.parameters != null) {
      m.addAll(finalizedPredicate.parameters);
    }

    columnValueMappers.forEach((PropertyValueMapper c) {
      m[c.columnName(withPrefix: valueKeyPrefix)] = c.value;
    });

    returningOrderedMappers.where((rm) => rm is RowMapper).forEach((rm) {
      m.addAll((rm as RowMapper).substitutionVariables);
    });

    return m;
  }

  List<ColumnMapper> get flattenedMappingElements {
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
      var variableName = m.columnName(withPrefix: "@$valueKeyPrefix", withTypeSuffix: true);
      return "$columnName=$variableName";
    }).join(",");
  }

  String get valuesColumnString {
    return columnValueMappers.map((c) => c.columnName()).join(",");
  }

  String get insertionValueString {
    return columnValueMappers.map((c) => c.columnName(withTypeSuffix: true, withPrefix: "@$valueKeyPrefix")).join(",");
  }

  String get joinString {
    return returningOrderedMappers.where((e) => e is RowMapper).map((e) => (e as RowMapper).joinString).join(" ");
  }

  String get returningColumnString {
    return flattenedMappingElements.map((p) => p.columnName(withTableNamespace: shouldAliasTables)).join(",");
  }

  String get orderByString {
    var allSortMappers = new List<SortMapper>.from(sortMappers);

    var nestedSorts = returningOrderedMappers.where((m) => m is RowMapper).expand((m) => (m as RowMapper).sortMappers);
    allSortMappers.addAll(nestedSorts);

    if (allSortMappers.length == 0) {
      return "";
    }

    return "ORDER BY ${allSortMappers.map((s) => s.orderByString).join(",")}";
  }

  PropertyValueMapper validatedColumnValueMapper(Map<String, dynamic> valueMap, String key) {
    var property = entity.properties[key];
    if (property == null) {
      throw new ArgumentError("Invalid query. Column '$key' does not exist for table '${entity.tableName}'");
    }

    if (property is ManagedRelationshipDescription) {
      if (property.relationshipType != ManagedRelationshipType.belongsTo) {
        return null;
      }

      var value = valueMap[key];
      if (value != null) {
        if (value is ManagedObject || value is Map) {
          return new PropertyValueMapper(this, property, value[property.destinationEntity.primaryKey]);
        }

        throw new ArgumentError("Invalid query. Column '$key' in '${entity.tableName}' does not exist. "
            "'$key' recognized as ORM relationship. Provided value must be 'Map' "
            "or ${property.destinationEntity.name}.");
      }
    }

    return new PropertyValueMapper(this, property, valueMap[key]);
  }

  QueryPredicate predicateFrom(
      List<QueryExpression<dynamic, dynamic>> expressions, List<QueryPredicate> predicates, List<RowMapper> createdImplicitRowMappers) {
    var matchers = propertyExpressionsFromObject(expressions, createdImplicitRowMappers);
    var allPredicates = matchers.expand((p) => [p.predicate]).toList();
    allPredicates.addAll(predicates.where((p) => p != null));
    return QueryPredicate.andPredicates(allPredicates);
  }

  int aliasCounter = 0;

  @override
  String generateTableAlias() {
    tableAlias ??= "t0";
    aliasCounter++;
    return "t$aliasCounter";
  }
}
