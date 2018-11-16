import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/expression.dart';
import 'package:aqueduct/src/db/postgresql/builders/sort.dart';
import 'package:aqueduct/src/db/postgresql/postgresql_query.dart';
import 'package:aqueduct/src/db/query/matcher_expression.dart';
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
            ? PredicateOperator.greaterThan
            : PredicateOperator.lessThan;
        final expr = ColumnExpressionBuilder(this, prop,
            ComparisonExpression(query.pageDescriptor.boundingValue, operator));
        columnExpressionBuilderNode = expr;
      }
    }

    query.subQueries?.forEach((relationshipDesc, subQuery) {
      addJoinTableBuilder(TableBuilder(subQuery as PostgresQuery,
          parent: this, joinedBy: relationshipDesc));
    });

    if (columnExpressionBuilderNode == null) {
      columnExpressionBuilderNode = addColumnExpressions(query.expression);
    } else {
      columnExpressionBuilderNode = ColumnExpressionBuilderANDNode(
          columnExpressionBuilderNode,
          addColumnExpressions(query.expression));
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
  ColumnExpressionBuilderNode columnExpressionBuilderNode;
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
    final expressionPredicate = queryPredicateFromNode(columnExpressionBuilderNode);

    predicate = _manualPredicate != null
    ? QueryPredicate.and([_manualPredicate, expressionPredicate])
    : queryPredicateFromNode(columnExpressionBuilderNode);

    if (predicate?.parameters != null) {
      variables.addAll(predicate.parameters);
    }

    returning.whereType<TableBuilder>().forEach((r) {
      r.finalize(variables);
    });
  }

  QueryPredicate queryPredicateFromNode(ColumnExpressionBuilderNode node) {
    if (node is ColumnExpressionBuilderANDNode) {
      return QueryPredicate.and(
          [queryPredicateFromNode(node.lhs), queryPredicateFromNode(node.rhs)]);
    }
    if (node is ColumnExpressionBuilderORNode) {
      return QueryPredicate.or(
          [queryPredicateFromNode(node.lhs), queryPredicateFromNode(node.rhs)]);
    }

    if ( node is ColumnExpressionBuilderGroupAndNode ) {
      return QueryPredicate.andGroup(queryPredicateFromNode(node.lhs), queryPredicateFromNode(node.rhs));
    }

    if ( node is ColumnExpressionBuilderGroupORNode ) {
      return QueryPredicate.orGroup(queryPredicateFromNode(node.lhs), queryPredicateFromNode(node.rhs));
    }

    if (node is ColumnExpressionBuilder) {
      return node.predicate;
    }

    return QueryPredicate.empty();
  }

  ColumnExpressionBuilderNode addColumnExpressions(
      QueryExpression<dynamic, dynamic, dynamic> expression) {
    if (expression == null) {
      return;
    }

    final predicateExpression = expression.expression;

    if (predicateExpression is AndGroupExpression) {
      return ColumnExpressionBuilderGroupAndNode(
          addColumnExpressions(predicateExpression.lhs),
          addColumnExpressions(predicateExpression.rhs)
      );
    }

    if (predicateExpression is OrGroupExpression) {
      return ColumnExpressionBuilderGroupORNode(
          addColumnExpressions(predicateExpression.lhs),
          addColumnExpressions(predicateExpression.rhs)
      );
    }

    if (predicateExpression is AndExpression) {
      return ColumnExpressionBuilderANDNode(
          addColumnExpressions(predicateExpression.lhs),
          addColumnExpressions(predicateExpression.rhs)
      );
    }

    if (predicateExpression is OrExpression) {
      return ColumnExpressionBuilderORNode(
          addColumnExpressions(predicateExpression.lhs),
          addColumnExpressions(predicateExpression.rhs)
      );
    }

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
        final expr =
        ColumnExpressionBuilder(this, lastElement, expression.expression);
        return expr;
      }
    } else if (isForeignKey) {
      // This will occur if we selected a belongs to relationship or a belongs to relationship's
      // primary key. In either case, this is a column in this table (a foreign key column).
      final expr = ColumnExpressionBuilder(
          this, expression.keyPath.path.first, expression.expression);
      return expr;
    }

    return addColumnExpressionToJoinedTable(expression);
  }

  ColumnExpressionBuilder addColumnExpressionToJoinedTable(
      QueryExpression<dynamic, dynamic, dynamic> expression) {
    TableBuilder joinedTable = _findJoinedTable(expression.keyPath);
    final lastElement = expression.keyPath.path.last;
    if (lastElement is ManagedRelationshipDescription) {
      final inversePrimaryKey = lastElement.inverse.entity.primaryKeyAttribute;
      final expr = ColumnExpressionBuilder(
          joinedTable, inversePrimaryKey, expression.expression,
          prefix: tableAlias);
      return expr;
    } else {
      final expr = ColumnExpressionBuilder(
          joinedTable, lastElement, expression.expression,
          prefix: tableAlias);
      return expr;
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
      final ManagedRelationshipDescription head = keyPath[0];
      TableBuilder join = returning
          .whereType<TableBuilder>()
          .firstWhere((m) => m.isJoinOnProperty(head), orElse: () => null);
      if (join == null) {
        join = TableBuilder.implicit(this, head);
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
    final columnExpressionTables = columnExpressionBuilderNode != null
        ? getTablesFromBuilderNode(columnExpressionBuilderNode)
        : [];

    if (columnExpressionTables.any((table) => joinedTables.contains(table))) {
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

  List<TableBuilder> getTablesFromBuilderNode(ColumnExpressionBuilderNode node) {
    if (node is ColumnExpressionCombiner) {
      final combinerNode = node as ColumnExpressionCombiner;
      return getTablesFromBuilderNode(combinerNode.lhs).addAll(getTablesFromBuilderNode(combinerNode.rhs));
    }

    return [(node as ColumnExpressionBuilder).table];
  }
}
