import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/managed/key_path.dart';

abstract class AbstractNode<E> {
  E lhs, rhs;
  AbstractNode(this.lhs, this.rhs);
}

abstract class AbstractLeaf {}


abstract class LogicalOperantNode<E> extends AbstractNode<E> {
  LogicalOperator operant;

  LogicalOperantNode(E lhs, E rhs, this.operant) : super(lhs, rhs);
}

abstract class ColumnExpressionLeaf implements ColumnExpression {}


enum LogicalOperator { and, or }

abstract class ColumnExpression {
  List<TableBuilder> get tables;
  ColumnExpressionNode or(ColumnExpression node);
  ColumnExpressionNode and(ColumnExpression node);
  QueryPredicate get predicate;
}

class ColumnExpressionNode extends LogicalOperantNode<ColumnExpression> implements ColumnExpression {
  bool isGrouped;

  ColumnExpressionNode(ColumnExpression lhs, ColumnExpression rhs, LogicalOperator logicalOperator, {this.isGrouped = false}) : super(lhs, rhs, logicalOperator);

  ColumnExpressionNode or(ColumnExpression node) => ColumnExpressionNode(this, node, LogicalOperator.or);
  ColumnExpressionNode and(ColumnExpression node) => ColumnExpressionNode(this, node, LogicalOperator.and);

  QueryPredicate get predicate => _getPredicateFromNode(this);

  static QueryPredicate _getPredicateFromNode(ColumnExpression expression) {
    if (expression is ColumnExpressionLeaf) {
      return expression.predicate;
    }

    if (expression is ColumnExpressionNode) {
      final logicalOperator = expression.operant;

      if (logicalOperator == LogicalOperator.and) {
        return QueryPredicate.and(
            [
              _getPredicateFromNode(expression.lhs),
              _getPredicateFromNode(expression.rhs)
            ],
            isGrouped: expression.isGrouped
        );
      }
      if (logicalOperator == LogicalOperator.or) {
        return QueryPredicate.or(
            [
              _getPredicateFromNode(expression.lhs),
              _getPredicateFromNode(expression.rhs)
            ],
            isGrouped: expression.isGrouped
        );
      }
    }

    return QueryPredicate.empty();
  }

  List<TableBuilder> get tables => _getTables(this);

  List<TableBuilder> _getTables(ColumnExpression node) {
    if (node is ColumnExpressionBuilder) {
      return [node.table];
    } else if (node is ColumnExpressionNode) {
      final tables = lhs.tables;
      if (rhs != null) {
        tables.addAll(rhs.tables);
      }
      return tables;
    } else {
      throw "Unkown Tree type: ${node.runtimeType}";
    }
  }
}

class ColumnExpressionBuilder extends ColumnBuilder implements ColumnExpressionLeaf {
  ColumnExpressionBuilder.property(TableBuilder table, this.expression, ManagedPropertyDescription property) :
      super.mixin(table, property);
  ColumnExpressionBuilder.keyPath(TableBuilder table, this.expression, KeyPath keyPath) :
        super.mixin(isOnJoinedTable(keyPath)
              ? _findJoinedTable(table, keyPath)
              : table,
          getProperty(keyPath)
      );

  static ColumnExpression query(TableBuilder table,
      QueryExpression expression) {

    final predicateExpression = expression.expression;

    if (predicateExpression is AndExpression<QueryExpression>) {
      return ColumnExpressionNode(
          ColumnExpressionBuilder.query(table, predicateExpression.operand),
          ColumnExpressionBuilder.query(table, predicateExpression.operand2),
          LogicalOperator.and,
          isGrouped: predicateExpression.isGrouped
      );
    } else if (predicateExpression is OrExpression<QueryExpression>) {
      return ColumnExpressionNode(
          ColumnExpressionBuilder.query(table, predicateExpression.operand),
          ColumnExpressionBuilder.query(table, predicateExpression.operand2),
          LogicalOperator.or,
          isGrouped: predicateExpression.isGrouped
      );
    } else {
      return ColumnExpressionBuilder.keyPath(
          table,
          expression.expression,
          expression.keyPath
      );
    }
  }

  static bool isOnJoinedTable(KeyPath keyPath) {
    final firstElement = keyPath.path.first;
    final lastElement = keyPath.path.last;

    bool isPropertyOnThisEntity = keyPath.length == 1;
    bool isForeignKey = keyPath.length == 2 &&
        lastElement is ManagedAttributeDescription &&
        lastElement.isPrimaryKey &&
        firstElement is ManagedRelationshipDescription &&
        firstElement.isBelongsTo;
    bool isBelongsTo = lastElement is ManagedRelationshipDescription &&
        lastElement.isBelongsTo;
    bool isColumn = lastElement is ManagedAttributeDescription || isBelongsTo;

    return (!((isPropertyOnThisEntity && isColumn) || // TODO: further understand to decmopose these into named variables
        isForeignKey)
        && !(keyPath.length == 0
            || (keyPath.length == 1 &&
                keyPath[0] is! ManagedRelationshipDescription)
        )
    );
  }

  static TableBuilder _findJoinedTable(TableBuilder table, KeyPath keyPath) {
    // creates & joins a TableBuilder for any relationship in keyPath
    // if it doesn't exist.
    if (keyPath.length == 0) {
      return table;
    } else if (keyPath.length == 1 && keyPath[0] is! ManagedRelationshipDescription) {
      return table;
    } else {
      final ManagedRelationshipDescription head = keyPath[0];
      TableBuilder join = table.returning
          .whereType<TableBuilder>()
          .firstWhere((m) => m.isJoinOnProperty(head), orElse: () => null);
      if (join == null) {
        join = TableBuilder.implicit(table, head);
        table.addJoinTableBuilder(join);
      }
      return _findJoinedTable(join, KeyPath.byRemovingFirstNKeys(keyPath, 1));
    }
  }

  static ManagedPropertyDescription getProperty(KeyPath keyPath) {
    final firstElement = keyPath.path.first;
    final lastElement = keyPath.path.last;

    bool isPropertyOnThisEntity = keyPath.length == 1;
    bool isForeignKey = keyPath.length == 2 &&
        lastElement is ManagedAttributeDescription &&
        lastElement.isPrimaryKey &&
        firstElement is ManagedRelationshipDescription &&
        firstElement.isBelongsTo;
    bool isBelongsTo = lastElement is ManagedRelationshipDescription &&
        lastElement.isBelongsTo;
    bool isColumn = lastElement is ManagedAttributeDescription || isBelongsTo;

    if (isPropertyOnThisEntity && isColumn) {
      // This will occur if we selected a column.
      return lastElement;
    } else if (isForeignKey) {
      // This will occur if we selected a belongs to relationship or a belongs to relationship's
      // primary key. In either case, this is a column in this table (a foreign key column).
      return firstElement;
    } else if (lastElement is ManagedRelationshipDescription) {
      final inversePrimaryKey = lastElement.inverse.entity.primaryKeyAttribute;
      return inversePrimaryKey;
    } else {
      return lastElement;
    }
  }

  PredicateExpression expression;

  String get defaultPrefix => "$prefix${table.sqlTableReference}_";

  String get prefix => table.tableAlias != null ? table.tableAlias : "";

  List<TableBuilder> get tables => [table];

  ColumnExpressionNode or(ColumnExpression node) => ColumnExpressionNode(this, node, LogicalOperator.or);
  ColumnExpressionNode and(ColumnExpression node) => ColumnExpressionNode(this, node, LogicalOperator.and);

  QueryPredicate get predicate {
    var expr = expression;
    if (expr is ComparisonExpression) {
      return comparisonPredicate(expr.operant, expr.operand);
    } else if (expr is RangeExpression) {
      return rangePredicate(expr.operand, expr.operand2, insideRange: expr.operant == RangeOperant.between);
    } else if (expr is NullCheckExpression) {
      return nullPredicate(isNull: expr.operand);
    } else if (expr is SetMembershipExpression) {
      return containsPredicate(expr.operand, within: expr.within);
    } else if (expr is StringExpression) {
      return stringPredicate(expr.operator, expr.operand,
          caseSensitive: expr.caseSensitive,
          invertOperator: expr.invertOperator);
    }

    throw UnsupportedError(
        "Unknown expression applied to 'Query'. '${expr.runtimeType}' is not supported by 'PostgreSQL'.");
  }

  QueryPredicate comparisonPredicate(
      ComparisonOperant operator, dynamic value) {
    var name = sqlColumnName(withTableNamespace: true);
    var variableName = sqlColumnName(withPrefix: defaultPrefix);

    return QueryPredicate(
        "$name ${ColumnBuilder.symbolTable[operator]} @$variableName$sqlTypeSuffix",
        {variableName: convertValueForStorage(value)});
  }

  QueryPredicate containsPredicate(Iterable<dynamic> values,
      {bool within = true}) {
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "$defaultPrefix${counter}_";

      var variableName = sqlColumnName(withPrefix: prefix);
      tokenList.add("@$variableName$sqlTypeSuffix");
      pairedMap[variableName] = convertValueForStorage(value);

      counter++;
    });

    var name = sqlColumnName(withTableNamespace: true);
    var keyword = within ? "IN" : "NOT IN";
    return QueryPredicate("$name $keyword (${tokenList.join(",")})", pairedMap);
  }

  QueryPredicate nullPredicate({bool isNull = true}) {
    var name = sqlColumnName(withTableNamespace: true);
    return QueryPredicate("$name ${isNull ? "ISNULL" : "NOTNULL"}", {});
  }

  QueryPredicate rangePredicate(dynamic lhsValue, dynamic rhsValue,
      {bool insideRange = true}) {
    var name = sqlColumnName(withTableNamespace: true);
    var lhsName = sqlColumnName(withPrefix: "${defaultPrefix}lhs_");
    var rhsName = sqlColumnName(withPrefix: "${defaultPrefix}rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return QueryPredicate(
        "$name $operation @$lhsName$sqlTypeSuffix AND @$rhsName$sqlTypeSuffix",
        {
          lhsName: convertValueForStorage(lhsValue),
          rhsName: convertValueForStorage(rhsValue)
        });
  }

  QueryPredicate stringPredicate(
      StringComparisonOperant operator, dynamic value,
      {bool caseSensitive = true, bool invertOperator = false}) {
    var n = sqlColumnName(withTableNamespace: true);
    var variableName = sqlColumnName(withPrefix: defaultPrefix);

    var matchValue = value;
    var operation = caseSensitive ? "LIKE" : "ILIKE";
    if (invertOperator) {
      operation = "NOT $operation";
    }
    switch (operator) {
      case StringComparisonOperant.beginsWith:
        matchValue = "$value%";
        break;
      case StringComparisonOperant.endsWith:
        matchValue = "%$value";
        break;
      case StringComparisonOperant.contains:
        matchValue = "%$value%";
        break;
      default:
        break;
    }

    return QueryPredicate("$n $operation @$variableName$sqlTypeSuffix",
        {variableName: matchValue});
  }
}
