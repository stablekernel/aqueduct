import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:aqueduct/src/db/query/matcher_expression.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/mixin.dart';
import 'package:aqueduct/src/db/query/predicate.dart';
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/shared/returnable.dart';
import 'package:aqueduct/src/db/shared/builders/column.dart';
import 'package:aqueduct/src/db/shared/builders/expression.dart';
import 'package:aqueduct/src/db/shared/builders/sort.dart';

class TableBuilder implements Returnable {
  TableBuilder(QueryMixin query, {this.parent, this.joinedBy, this.dbWrapper})
      : entity = query.entity,
        _manualPredicate = query.predicate {
    if (parent != null) {
      tableAlias = createTableAlias();
    }
    returning =
        ColumnBuilder.fromKeys(this, query.propertiesToFetch ?? [], dbWrapper);

    columnSortBuilders = query.sortDescriptors
            ?.map((s) => ColumnSortBuilder(dbWrapper, this, s.key, s.order))
            ?.toList() ??
        [];

    if (query.pageDescriptor != null) {
      columnSortBuilders.add(ColumnSortBuilder(dbWrapper, this,
          query.pageDescriptor.propertyName, query.pageDescriptor.order));

      if (query.pageDescriptor.boundingValue != null) {
        final prop = entity.properties[query.pageDescriptor.propertyName];
        final operator = query.pageDescriptor.order == QuerySortOrder.ascending
            ? PredicateOperator.greaterThan
            : PredicateOperator.lessThan;
        final expr = dbWrapper.getColumnExpressionBuilder(this, prop,
            ComparisonExpression(query.pageDescriptor.boundingValue, operator));
        // final expr = ColumnExpressionBuilder(dbWrapper,this, prop,
        //     ComparisonExpression(query.pageDescriptor.boundingValue, operator));
        expressionBuilders.add(expr);
      }
    }

    query.subQueries?.forEach((relationshipDesc, subQuery) {
      addJoinTableBuilder(TableBuilder(subQuery as QueryMixin,
          parent: this, joinedBy: relationshipDesc));
    });

    addColumnExpressions(query.expressions);
  }

  TableBuilder.implicit(this.parent, this.joinedBy, this.dbWrapper)
      : entity = joinedBy.inverse.entity,
        _manualPredicate = QueryPredicate.empty() {
    tableAlias = createTableAlias();
    returning = <Returnable>[];
    columnSortBuilders = [];
  }

  final ManagedEntity entity;
  final TableBuilder parent;
  final ManagedRelationshipDescription joinedBy;
  final List<ColumnExpressionBuilder> expressionBuilders = [];
  String tableAlias;
  QueryPredicate predicate;
  List<ColumnSortBuilder> columnSortBuilders;
  List<Returnable> returning;
  int aliasCounter = 0;

  final QueryPredicate _manualPredicate;
  final DbWrapper dbWrapper;

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
      left = ColumnBuilder(dbWrapper, parent, joinedBy);
      right = ColumnBuilder(dbWrapper, this, entity.primaryKeyAttribute);
    } else {
      left =
          ColumnBuilder(dbWrapper, parent, parent.entity.primaryKeyAttribute);
      right = ColumnBuilder(dbWrapper, this, joinedBy.inverse);
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
    final allExpressions = [_manualPredicate]
      ..addAll(expressionBuilders.map((c) => c.predicate));

    predicate = QueryPredicate.and(allExpressions);
    if (predicate?.parameters != null) {
      variables.addAll(predicate.parameters);
    }

    returning.whereType<TableBuilder>().forEach((r) {
      r.finalize(variables);
    });
  }

  void addColumnExpressions(
      List<QueryExpression<dynamic, dynamic>> expressions) {
    if (expressions == null) {
      return;
    }

    expressions.forEach((expression) {
      final firstElement = expression.keyPath.path.first;
      final lastElement = expression.keyPath.path.last;

      bool isPropertyOnThisEntity = expression.keyPath.length == 1;
      bool isForeignKey = expression.keyPath.length == 2 &&
          lastElement is ManagedAttributeDescription &&
          lastElement.isPrimaryKey &&
          firstElement is ManagedRelationshipDescription &&
          firstElement.isBelongsTo;

      if (isPropertyOnThisEntity) {
        bool isBelongsTo = lastElement is ManagedRelationshipDescription &&
            lastElement.isBelongsTo;
        bool isColumn =
            lastElement is ManagedAttributeDescription || isBelongsTo;

        if (isColumn) {
          // This will occur if we selected a column.
          // final expr = ColumnExpressionBuilder(
          //     dbWrapper, this, lastElement, expression.expression);
          final expr = dbWrapper.getColumnExpressionBuilder(
              this, lastElement, expression.expression);
          expressionBuilders.add(expr);
          return;
        }
      } else if (isForeignKey) {
        // This will occur if we selected a belongs to relationship or a belongs to relationship's
        // primary key. In either case, this is a column in this table (a foreign key column).
        // final expr = ColumnExpressionBuilder(dbWrapper, this,
        //     expression.keyPath.path.first, expression.expression);
        final expr = dbWrapper.getColumnExpressionBuilder(
            this, expression.keyPath.path.first, expression.expression);
        expressionBuilders.add(expr);
        return;
      }

      addColumnExpressionToJoinedTable(expression);
    });
  }

  void addColumnExpressionToJoinedTable(
      QueryExpression<dynamic, dynamic> expression) {
    TableBuilder joinedTable = _findJoinedTable(expression.keyPath);
    final lastElement = expression.keyPath.path.last;
    if (lastElement is ManagedRelationshipDescription) {
      final inversePrimaryKey = lastElement.inverse.entity.primaryKeyAttribute;
      // final expr = ColumnExpressionBuilder(
      //     dbWrapper, joinedTable, inversePrimaryKey, expression.expression,
      //     prefix: tableAlias);
      final expr = dbWrapper.getColumnExpressionBuilder(
          joinedTable, inversePrimaryKey, expression.expression,
          prefix: tableAlias);
      expressionBuilders.add(expr);
    } else {
      // final expr = ColumnExpressionBuilder(
      //     dbWrapper, joinedTable, lastElement, expression.expression,
      //     prefix: tableAlias);
      final expr=dbWrapper.getColumnExpressionBuilder(joinedTable, lastElement, expression.expression);
      expressionBuilders.add(expr);
    }
  }

  TableBuilder _findJoinedTable(KeyPath keyPath) {
    // creates & joins a TableBuilder for any relationship in keyPath
    // if it doesn't exist.
    if (keyPath.length == 0) {
      return this;
    } else if (keyPath.length == 1 &&
        keyPath[0] is! ManagedRelationshipDescription) {
      return this;
    } else {
      final head = keyPath[0] as ManagedRelationshipDescription;
      TableBuilder join = returning
          .whereType<TableBuilder>()
          .firstWhere((m) => m.isJoinOnProperty(head), orElse: () => null);
      if (join == null) {
        join = TableBuilder.implicit(this, head, dbWrapper);
        addJoinTableBuilder(join);
      }
      return join._findJoinedTable(KeyPath.byRemovingFirstNKeys(keyPath, 1));
    }
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
    if (expressionBuilders.any((e) => joinedTables.contains(e.table))) {
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
