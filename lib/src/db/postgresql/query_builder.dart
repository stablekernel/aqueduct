import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/row.dart';
import 'package:aqueduct/src/db/postgresql/builders/sort.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/postgresql/builders/value.dart';

import '../db.dart';
import '../query/sort_descriptor.dart';
import 'row_instantiator.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

class PostgresQueryBuilder extends Object with RowInstantiator, TableBuilder {
  static const String valueKeyPrefix = "v_";

  PostgresQueryBuilder(this.entity,
      {List<KeyPath> returningProperties,
      Map<String, dynamic> values,
      List<QueryExpression<dynamic, dynamic>> expressions,
      QueryPredicate predicate,
      List<TableRowBuilder> joinedRowMappers,
      List<QuerySortDescriptor> sortDescriptors,
      bool aliasTables: false}) {
    if (aliasTables) {
      shouldAliasTables = true;
      tableAlias = "t0";
    }

    if (returningProperties == null) {
      orderedReturnMappers = [];
    } else {
      orderedReturnMappers = ColumnBuilder.fromKeys(this, returningProperties);
    }

    this.sortMappers = sortDescriptors?.map((s) => new ColumnSortBuilder(this, entity.properties[s.key], s.order))?.toList();

    if (joinedRowMappers != null) {
      orderedReturnMappers.addAll(joinedRowMappers);
      joinedRowMappers.forEach((rm) {
        rm.originatingTable = this;

        // If we're joining on belongsTo relationship, ensure
        // that foreign key column gets ignored during instantiation.
        // It'll get populated by the joined table.
        orderedReturnMappers.where((m) {
          if (m is ColumnBuilder) {
            return identical(m.property, rm.joiningProperty);
          }

          return false;
        }).forEach((m) {
          (m as ColumnBuilder).fetchAsForeignKey = true;
        });
      });
    }

    columnValueMappers =
        values?.keys?.map((key) => validatedColumnValueMapper(values, key))?.where((v) => v != null)?.toList() ?? [];

    var implicitJoins = <TableRowBuilder>[];
    finalizedPredicate = predicateFrom(expressions, [predicate], implicitJoins);
    orderedReturnMappers.addAll(implicitJoins);
  }

  bool shouldAliasTables = false;

  List<ColumnValueBuilder> columnValueMappers;
  QueryPredicate finalizedPredicate;
  List<ColumnSortBuilder> sortMappers;

  @override
  ManagedEntity entity;

  @override
  String tableAlias;

  @override
  TableBuilder get rootTableMapper => this;

  String get primaryTableDefinition => tableDefinition;

  bool get containsJoins => orderedReturnMappers.reversed.any((p) => p is TableRowBuilder);

  String get whereClause => finalizedPredicate?.format;

  Map<String, dynamic> get substitutionValueMap {
    var m = <String, dynamic>{};
    if (finalizedPredicate?.parameters != null) {
      m.addAll(finalizedPredicate.parameters);
    }

    columnValueMappers.forEach((ColumnValueBuilder c) {
      m[c.columnName(withPrefix: valueKeyPrefix)] = c.value;
    });

    orderedReturnMappers.where((rm) => rm is TableRowBuilder).forEach((rm) {
      m.addAll((rm as TableRowBuilder).substitutionVariables);
    });

    return m;
  }

  List<ColumnBuilder> get flattenedReturnMappers {
    return orderedReturnMappers.expand((c) {
      if (c is TableRowBuilder) {
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
    return orderedReturnMappers.where((e) => e is TableRowBuilder).map((e) => (e as TableRowBuilder).joinString).join(" ");
  }

  String get returningColumnString {
    return flattenedReturnMappers.map((p) => p.columnName(withTableNamespace: shouldAliasTables)).join(",");
  }

  String get orderByString {
    var allSortMappers = new List<ColumnSortBuilder>.from(sortMappers);

    var nestedSorts = orderedReturnMappers.where((m) => m is TableRowBuilder).expand((m) => (m as TableRowBuilder).sortMappers);
    allSortMappers.addAll(nestedSorts);

    if (allSortMappers.length == 0) {
      return "";
    }

    return "ORDER BY ${allSortMappers.map((s) => s.orderByString).join(",")}";
  }

  ColumnValueBuilder validatedColumnValueMapper(Map<String, dynamic> valueMap, String key) {
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
          return new ColumnValueBuilder(this, property, value[property.destinationEntity.primaryKey]);
        }

        throw new ArgumentError("Invalid query. Column '$key' in '${entity.tableName}' does not exist. "
            "'$key' recognized as ORM relationship. Provided value must be 'Map' "
            "or ${property.destinationEntity.name}.");
      }
    }

    return new ColumnValueBuilder(this, property, valueMap[key]);
  }

  QueryPredicate predicateFrom(
      List<QueryExpression<dynamic, dynamic>> expressions, List<QueryPredicate> predicates, List<TableRowBuilder> createdImplicitRowMappers) {
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
