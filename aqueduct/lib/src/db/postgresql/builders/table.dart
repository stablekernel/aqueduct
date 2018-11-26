import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/expression.dart';
import 'package:aqueduct/src/db/postgresql/builders/sort.dart';
import 'package:aqueduct/src/db/postgresql/postgresql_query.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/predicate.dart';
import 'package:aqueduct/src/db/query/query.dart';

class TableBuilder implements Returnable {
  TableBuilder(PostgresQuery query, {this.parent, this.joinedBy})
      : entity = query.entity,
        _manualPredicate = query.predicate {
    if (parent != null) {
      tableAlias = createTableAlias();
    }
    returning = ColumnBuilder.fromKeys(this, query.propertiesToFetch ?? []);

    columnSortBuilders = query.sortDescriptors
            ?.map((s) => ColumnSortBuilder(this, s.key, s.order))
            ?.toList() ??
        [];

    if (query.pageDescriptor != null) {
      columnSortBuilders.add(ColumnSortBuilder(
          this, query.pageDescriptor.propertyName, query.pageDescriptor.order));

      if (query.pageDescriptor.boundingValue != null) {
        final prop = entity.properties[query.pageDescriptor.propertyName];
        final operator = query.pageDescriptor.order == QuerySortOrder.ascending
            ? ComparisonOperant.greaterThan
            : ComparisonOperant.lessThan;
        final expr = ColumnExpressionBuilder.property(
            this,
            ComparisonExpression(query.pageDescriptor.boundingValue, operator),
            prop
        );
        columnExpressionBuilder = expr;
      }
    }

    query.subQueries?.forEach((relationshipDesc, subQuery) {
      addJoinTableBuilder(TableBuilder(subQuery as PostgresQuery,
          parent: this, joinedBy: relationshipDesc));
    });

    final predicateExpression = query.expression;

    if (predicateExpression == null) {
      return;
    }

    if (columnExpressionBuilder != null) {
      columnExpressionBuilder.expressionTree = query.expression;
    } else {
      columnExpressionBuilder = ColumnExpressionBuilder(this, query.expression);
    }
  }

  TableBuilder.implicit(this.parent, this.joinedBy)
      : entity = joinedBy.inverse.entity,
        _manualPredicate = QueryPredicate.empty() {
    tableAlias = createTableAlias();
    returning = <Returnable>[];
    columnSortBuilders = [];
  }

  final ManagedEntity entity;
  final TableBuilder parent;
  final ManagedRelationshipDescription joinedBy;
  ColumnExpressionBuilder columnExpressionBuilder;
  String tableAlias;
  QueryPredicate predicate;
  List<ColumnSortBuilder> columnSortBuilders;
  List<Returnable> returning;
  int aliasCounter = 0;

  final QueryPredicate _manualPredicate;

  ManagedRelationshipDescription get foreignKeyProperty =>
      joinedBy.relationshipType == ManagedRelationshipType.belongsTo
          ? joinedBy
          : joinedBy.inverse;

  bool isJoinOnProperty(ManagedRelationshipDescription relationship) {
    return joinedBy.destinationEntity == relationship.destinationEntity &&
        joinedBy.entity == relationship.entity &&
        joinedBy.name == relationship.name;
  }

  List<ColumnBuilder> get flattenedColumnsToReturn {
    return returning.fold(<ColumnBuilder>[], (prev, c) {
      if (c is TableBuilder) {
        prev.addAll(c.flattenedColumnsToReturn);
      } else if (c is ColumnBuilder) {
        prev.add(c);
      }
      return prev;
    });
  }

  QueryPredicate get joiningPredicate {
    ColumnBuilder left, right;
    if (identical(foreignKeyProperty, joinedBy)) {
      left = ColumnBuilder(parent, joinedBy);
      right = ColumnBuilder(this, entity.primaryKeyAttribute);
    } else {
      left = ColumnBuilder(parent, parent.entity.primaryKeyAttribute);
      right = ColumnBuilder(this, joinedBy.inverse);
    }

    var leftColumn = left.sqlColumnName(withTableNamespace: true);
    var rightColumn = right.sqlColumnName(withTableNamespace: true);
    return QueryPredicate("$leftColumn=$rightColumn", null);
  }

  String createTableAlias() {
    if (parent != null) {
      return parent.createTableAlias();
    }

    tableAlias ??= "t0";
    aliasCounter++;
    return "t$aliasCounter";
  }

  void finalize(Map<String, dynamic> variables) {
    final expressionPredicate = columnExpressionBuilder != null
        ? columnExpressionBuilder.predicate
        : QueryPredicate.empty();

    predicate = _manualPredicate != null
    ? QueryPredicate.and([_manualPredicate, expressionPredicate])
    : expressionPredicate;

    if (predicate?.parameters != null) {
      variables.addAll(predicate.parameters);
    }

    returning.whereType<TableBuilder>().forEach((r) {
      r.finalize(variables);
    });
  }

  void addJoinTableBuilder(TableBuilder r) {
    returning.add(r);

    // If we're fetching the primary key of the joined table, remove
    // the foreign key from the columns returning from this table.
    // They are the same value, but this guarantees the row instantiator
    // that it only sees the value once and makes its logic more straightforward.
    if (r.returning.isNotEmpty) {
      returning.removeWhere((m) {
        if (m is ColumnBuilder) {
          return identical(m.property, r.joinedBy);
        }

        return false;
      });
    }

    columnSortBuilders.addAll(r.columnSortBuilders);
  }

  /*
      Methods that return portions of a SQL statement for this object
   */

  String get sqlTableName {
    if (tableAlias == null) {
      return entity.tableName;
    }

    return "${entity.tableName} $tableAlias";
  }

  String get sqlTableReference => tableAlias ?? entity.tableName;

  String get sqlInnerSelect {
    var nestedJoins =
        returning.whereType<TableBuilder>().map((t) => t.sqlJoin).join(" ");

    var flattenedColumns = flattenedColumnsToReturn;

    var columnsWithNamespace = flattenedColumns
        .map((p) => p.sqlColumnName(withTableNamespace: true))
        .join(",");
    var columnsWithoutNamespace =
        flattenedColumns.map((p) => p.sqlColumnName()).join(",");

    var outerWhereString = " WHERE ${predicate.format}";
    var selectString =
        "SELECT $columnsWithNamespace FROM $sqlTableName $nestedJoins";
    var alias = "$sqlTableReference($columnsWithoutNamespace)";
    return "LEFT OUTER JOIN ($selectString$outerWhereString) $alias ON ${joiningPredicate.format}";
  }

  String get sqlJoin {
    if (parent == null) {
      return returning
          .whereType<TableBuilder>()
          .map((e) => e.sqlJoin)
          .join(" ");
    }

    // At this point, we know that this table is being joined.
    // If we have a predicate that references a column in a joined table,
    // then we can't use a simple join, we have to use an inner select.
    final joinedTables = returning.whereType<TableBuilder>().toList();

    if (columnExpressionBuilder != null
        && columnExpressionBuilder.tables.any(joinedTables.contains)) {
      return sqlInnerSelect;
    }

    final totalJoinPredicate =
        QueryPredicate.and([joiningPredicate, predicate]);
    var thisJoin =
        "LEFT OUTER JOIN $sqlTableName ON ${totalJoinPredicate.format}";

    if (returning.any((p) => p is TableBuilder)) {
      var nestedJoins = returning.whereType<TableBuilder>().map((p) {
        return p.sqlJoin;
      }).toList();
      nestedJoins.insert(0, thisJoin);
      return nestedJoins.join(" ");
    }

    return thisJoin;
  }
}
