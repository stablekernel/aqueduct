import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/postgresql/builders/expression.dart';
import 'package:aqueduct/src/db/postgresql/builders/sort.dart';
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/query/sort_descriptor.dart';

import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

class TableRowBuilder extends Returnable with TableBuilder {
  TableRowBuilder(this.type, this.joiningProperty, List<KeyPath> propertiesToFetch,
      {this.predicate, this.expressions, List<QuerySortDescriptor> sortDescriptors}) {
    orderedReturnMappers = ColumnBuilder.fromKeys(this, propertiesToFetch);
    _sortMappers = sortDescriptors?.map((s) => new ColumnSortBuilder(this, entity.properties[s.key], s.order))?.toList();
  }

  TableRowBuilder.implicit(this.type, this.joiningProperty, this.originatingTable) {
    orderedReturnMappers = [];
  }

  ManagedRelationshipDescription joiningProperty;
  TableBuilder originatingTable;
  PersistentJoinType type;
  List<QueryExpression<dynamic, dynamic>> expressions;
  QueryPredicate predicate;
  QueryPredicate _joinCondition;
  List<ColumnSortBuilder> _sortMappers;
  List<TableRowBuilder> _implicitRowMappers;
  List<ColumnExpressionBuilder> _matcherExpressions;

  @override
  ManagedEntity get entity => joiningProperty.inverse.entity;

  ManagedRelationshipDescription get foreignKeyProperty =>
      joiningProperty.relationshipType == ManagedRelationshipType.belongsTo ? joiningProperty : joiningProperty.inverse;

  List<ColumnSortBuilder> get sortMappers {
    var allSortMappers = _sortMappers ?? <ColumnSortBuilder>[];
    orderedReturnMappers.where((p) => p is TableRowBuilder).forEach((p) {
      allSortMappers.addAll((p as TableRowBuilder).sortMappers);
    });
    return allSortMappers;
  }

  Map<String, dynamic> get substitutionVariables {
    var variables = joinCondition.parameters ?? {};
    orderedReturnMappers.where((p) => p is TableRowBuilder).forEach((p) {
      variables.addAll((p as TableRowBuilder).substitutionVariables);
    });
    matcherExpressions.where((expr) => !identical(expr.table, this)).forEach((expr) {
      if (expr.predicate?.parameters != null) {
        variables.addAll(expr.predicate.parameters);
      }
    });

    return variables;
  }

  List<ColumnBuilder> get flattened {
    return orderedReturnMappers.fold([], (prev, c) {
      if (c is TableRowBuilder) {
        prev.addAll(c.flattened);
      } else {
        prev.add(c);
      }
      return prev;
    });
  }

  List<TableRowBuilder> get implicitRowMappers {
    if (_implicitRowMappers == null) {
      _buildMatcher();
    }

    return _implicitRowMappers;
  }

  List<ColumnExpressionBuilder> get matcherExpressions {
    if (_matcherExpressions == null) {
      _buildMatcher();
    }

    return _matcherExpressions;
  }

  QueryPredicate get joinCondition {
    if (_joinCondition == null) {
      ColumnBuilder leftMapper, rightMapper;
      if (identical(foreignKeyProperty, joiningProperty)) {
        leftMapper = new ColumnBuilder(originatingTable, joiningProperty);
        rightMapper = new ColumnBuilder(this, entity.primaryKeyAttribute);
      } else {
        leftMapper = new ColumnBuilder(originatingTable, originatingTable.entity.primaryKeyAttribute);
        rightMapper = new ColumnBuilder(this, joiningProperty.inverse);
      }

      var leftColumn = leftMapper.columnName(withTableNamespace: true);
      var rightColumn = rightMapper.columnName(withTableNamespace: true);
      var joinPredicate = new QueryPredicate("$leftColumn=$rightColumn", null);
      var filterPredicates =
          matcherExpressions.where((expr) => identical(expr.table, this)).map((expr) => expr.predicate).toList();
      filterPredicates.add(joinPredicate);
      if (predicate != null) {
        filterPredicates.add(predicate);
      }
      _joinCondition = QueryPredicate.andPredicates(filterPredicates);
    }

    return _joinCondition;
  }

  void addRowMappers(List<TableRowBuilder> rowMappers, {bool areImplicit: false}) {
    rowMappers.forEach((r) {
      if (!areImplicit) {
        orderedReturnMappers.where((m) {
          if (m is ColumnBuilder) {
            return identical(m.property, r.joiningProperty);
          }

          return false;
        }).forEach((m) {
          (m as ColumnBuilder).fetchAsForeignKey = true;
        });
      } else {
        _implicitRowMappers ??= <TableRowBuilder>[];
        validateImplicitRowMapper(r);
        _implicitRowMappers.add(r);
      }

      r.originatingTable = this;
    });
    orderedReturnMappers.addAll(rowMappers);
  }

  void validateImplicitRowMapper(TableRowBuilder rowMapper) {
    // Check implicit row mappers for cycles
    var parentTable = originatingTable;
    while (parentTable != null) {
      var inverseMapper = parentTable.orderedReturnMappers.reversed.where((pm) => pm is TableRowBuilder).firstWhere((pm) {
        return identical(rowMapper.joiningProperty.inverse, (pm as TableRowBuilder).joiningProperty);
      }, orElse: () => null);

      if (inverseMapper != null) {
        throw new ArgumentError("Invalid query. This query would join on the same table and foreign key twice. "
            "The offending query has a 'where' matcher on '${rowMapper.entity.tableName}.${rowMapper.joiningProperty
                .name}',"
            "but this matcher should be on a parent 'Query'.");
      }

      if (parentTable is TableRowBuilder) {
        parentTable = (parentTable as TableRowBuilder).originatingTable;
      } else {
        parentTable = null;
      }
    }
  }

  String get innerSelectString {
    var nestedJoins =
        orderedReturnMappers.where((m) => m is TableRowBuilder).map((rm) => (rm as TableRowBuilder).joinString).join(" ");

    var flattenedColumns = flattened;
    var columnsWithNamespace = flattenedColumns.map((p) => p.columnName(withTableNamespace: true)).join(",");
    var columnsWithoutNamespace = flattenedColumns.map((p) => p.columnName()).join(",");

    var outerWhere = QueryPredicate
        .andPredicates(matcherExpressions.where((expr) => !identical(expr.table, this)).map((expr) => expr.predicate));
    var outerWhereString = "";
    if (outerWhere != null) {
      outerWhereString = " WHERE ${outerWhere.format}";
    }

    var selectString = "SELECT $columnsWithNamespace FROM $tableDefinition $nestedJoins";
    var alias = "$tableReference($columnsWithoutNamespace)";
    return "LEFT OUTER JOIN ($selectString$outerWhereString) $alias ON ${joinCondition.format}";
  }

  String get joinString {
    if ((implicitRowMappers?.length ?? 0) > 0) {
      return innerSelectString;
    }

    var thisJoin = "LEFT OUTER JOIN $tableDefinition ON ${joinCondition.format}";

    if (orderedReturnMappers.any((p) => p is TableRowBuilder)) {
      var nestedJoins = orderedReturnMappers.where((p) => p is TableRowBuilder).map((p) {
        return (p as TableRowBuilder).joinString;
      }).toList();
      nestedJoins.insert(0, thisJoin);
      return nestedJoins.join(" ");
    }

    return thisJoin;
  }

  bool get isToMany {
    return joiningProperty.relationshipType == ManagedRelationshipType.hasMany;
  }

  bool isJoinOnProperty(ManagedRelationshipDescription relationship) {
    return joiningProperty.destinationEntity == relationship.destinationEntity &&
        joiningProperty.entity == relationship.entity &&
        joiningProperty.name == relationship.name;
  }

  @override
  String generateTableAlias() {
    return originatingTable.generateTableAlias();
  }

  @override
  String toString() {
    return "RowMapper on $joiningProperty: $orderedReturnMappers";
  }

  void _buildMatcher() {
    var rowMappers = <TableRowBuilder>[];
    _matcherExpressions = propertyExpressionsFromObject(expressions, rowMappers);

    addRowMappers(rowMappers, areImplicit: true);
  }

}
