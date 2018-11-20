import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/managed/key_path.dart';

//abstract class AbstractNode<E> {
//  E element;
//  AbstractBranch branch;
//  AbstractNode(this.element, {this.branch})
//}

abstract class Tree {
  List<TableBuilder> get tables;
  ColumnExpressionNode or(Tree node);
  ColumnExpressionNode and(Tree node);
  QueryPredicate get predicate;
}

abstract class AbstractLeaf implements Tree {}

abstract class AbstractNode<E> implements Tree {
  E lhs, rhs;
  LogicalOperator logicalOperator;

  AbstractNode(this.lhs, this.rhs, this.logicalOperator);
}


enum LogicalOperator { and, or }

//abstract class JunctionCreatorMixin implements AbstractColumnExpressionNode {
//  ColumnExpressionNode or(ColumnExpressionNode node) => ColumnExpressionNode.branch(this, rhs: node, logicalOperator: LogicalOperator.or);
//  ColumnExpressionNode and(ColumnExpressionNode node) => ColumnExpressionNode.branch(this, rhs: node, logicalOperator: LogicalOperator.and);
//}

class ColumnExpressionNode extends AbstractNode<Tree>  { //with JunctionCreatorMixin
  bool isGrouped;

  ColumnExpressionNode(Tree lhs, Tree rhs, LogicalOperator logicalOperator, {this.isGrouped = false}) : super(lhs, rhs, logicalOperator);

  // We want this stuff mixed in

  ColumnExpressionNode or(Tree node) => ColumnExpressionNode(this, node, LogicalOperator.or);
  ColumnExpressionNode and(Tree node) => ColumnExpressionNode(this, node, LogicalOperator.and);

  QueryPredicate get predicate => _getPredicateFromNode(this);

  static QueryPredicate _getPredicateFromNode(ColumnExpressionNode node) {
      final logicalOperator = node.logicalOperator;

      if (logicalOperator == null) {
        return node.predicate;
      }

      if (logicalOperator == LogicalOperator.and) {
        return QueryPredicate.and(
            [
              getPredicateFromNode(node.lhs),
              getPredicateFromNode(node.rhs)
            ],
            isGrouped: node.isGrouped
        );
      }
      if (logicalOperator == LogicalOperator.or) {
        return QueryPredicate.or(
            [
              getPredicateFromNode(node.lhs),
              getPredicateFromNode(node.rhs)
            ],
            isGrouped: node.isGrouped
        );
      }

    return QueryPredicate.empty();
  }

  List<TableBuilder> get tables => _getTables(this);

  List<TableBuilder> _getTables(Tree node) {
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

class ColumnExpressionBuilder extends ColumnBuilder implements AbstractLeaf {
  ColumnExpressionBuilder.property(TableBuilder table, this.expression, ManagedPropertyDescription property) :
      super.mixin(table, property);
  ColumnExpressionBuilder.keyPath(TableBuilder table, this.expression, KeyPath keyPath) :
        super.mixin(isOnJoinedTable(keyPath)
              ? _findJoinedTable(table, keyPath)
              : table,
          getProperty(keyPath)
      );

  static Tree query(TableBuilder table,
      QueryExpression expression) {

    final predicateExpression = expression.expression;

    if (predicateExpression is AndExpression) {
      return ColumnExpressionNode(
          ColumnExpressionBuilder.query(table, predicateExpression.lhs),
          ColumnExpressionBuilder.query(table, predicateExpression.rhs),
          LogicalOperator.and
      );
    } else if (predicateExpression is AndGroupExpression) {
    return ColumnExpressionNode(
        ColumnExpressionBuilder.query(table, predicateExpression.lhs),
        ColumnExpressionBuilder.query(table, predicateExpression.rhs),
        LogicalOperator.and,
        isGrouped: true
    );
    } else if (predicateExpression is OrExpression) {
      return ColumnExpressionNode(
          ColumnExpressionBuilder.query(table, predicateExpression.lhs),
          ColumnExpressionBuilder.query(table, predicateExpression.rhs),
          LogicalOperator.or
      );
    } else if (predicateExpression is OrGroupExpression) {
      return ColumnExpressionNode(
          ColumnExpressionBuilder.query(table, predicateExpression.lhs),
          ColumnExpressionBuilder.query(table, predicateExpression.rhs),
          LogicalOperator.or,
          isGrouped: true
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

  ColumnExpressionNode or(Tree node) => ColumnExpressionNode(this, node, LogicalOperator.or);
  ColumnExpressionNode and(Tree node) => ColumnExpressionNode(this, node, LogicalOperator.and);

  QueryPredicate get predicate {
    var expr = expression;
    if (expr is ComparisonExpression) {
      return comparisonPredicate(expr.operator, expr.value);
    } else if (expr is RangeExpression) {
      return rangePredicate(expr.lhs, expr.rhs, insideRange: expr.within);
    } else if (expr is NullCheckExpression) {
      return nullPredicate(isNull: expr.shouldBeNull);
    } else if (expr is SetMembershipExpression) {
      return containsPredicate(expr.values, within: expr.within);
    } else if (expr is StringExpression) {
      return stringPredicate(expr.operator, expr.value,
          caseSensitive: expr.caseSensitive,
          invertOperator: expr.invertOperator);
    }

    throw UnsupportedError(
        "Unknown expression applied to 'Query'. '${expr.runtimeType}' is not supported by 'PostgreSQL'.");
  }

  QueryPredicate comparisonPredicate(
      PredicateOperator operator, dynamic value) {
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
      PredicateStringOperator operator, dynamic value,
      {bool caseSensitive = true, bool invertOperator = false}) {
    var n = sqlColumnName(withTableNamespace: true);
    var variableName = sqlColumnName(withPrefix: defaultPrefix);

    var matchValue = value;
    var operation = caseSensitive ? "LIKE" : "ILIKE";
    if (invertOperator) {
      operation = "NOT $operation";
    }
    switch (operator) {
      case PredicateStringOperator.beginsWith:
        matchValue = "$value%";
        break;
      case PredicateStringOperator.endsWith:
        matchValue = "%$value";
        break;
      case PredicateStringOperator.contains:
        matchValue = "%$value%";
        break;
      default:
        break;
    }

    return QueryPredicate("$n $operation @$variableName$sqlTypeSuffix",
        {variableName: matchValue});
  }
}
