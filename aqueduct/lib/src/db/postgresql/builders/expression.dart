import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/managed/key_path.dart';

abstract class ColumnExpressionBuilderNode
    implements ColumnExpressionWithTables, ColumnExpressionWithPredicate {
  ColumnExpressionBuilderORNode or(ColumnExpressionBuilderNode builder);
  ColumnExpressionBuilderANDNode and(ColumnExpressionBuilderNode builder);
}

abstract class AbstractColumnExpressionCombiner {
  ColumnExpressionBuilderNode lhs;
  ColumnExpressionBuilderNode rhs;
  AbstractColumnExpressionCombiner(this.lhs, this.rhs);
}

abstract class ColumnExpressionWithPredicate {
  QueryPredicate get predicate;
}

abstract class ColumnExpressionWithPredicateMixin
    implements ColumnExpressionBuilderNode {
  QueryPredicate get predicate => getPredicateFromNode(this);

  static QueryPredicate getPredicateFromNode(ColumnExpressionBuilderNode node) {
    if (node is ColumnExpressionBuilder) {
      return node.predicate;
    }
    if (node is ColumnExpressionBuilderANDNode) {
      return QueryPredicate.and([
        getPredicateFromNode(node.lhs),
        getPredicateFromNode(node.rhs)
      ]);
    }
    if (node is ColumnExpressionBuilderORNode) {
      return QueryPredicate.or([
        getPredicateFromNode(node.lhs),
        getPredicateFromNode(node.rhs)
      ]);
    }
    if (node is ColumnExpressionBuilderGroupAndNode) {
      return QueryPredicate.andGroup(
          getPredicateFromNode(node.lhs),
          getPredicateFromNode(node.rhs)
      );
    }
    if (node is ColumnExpressionBuilderGroupORNode) {
      return QueryPredicate.orGroup(
          getPredicateFromNode(node.lhs),
          getPredicateFromNode(node.rhs)
      );
    }

    return QueryPredicate.empty();
  }
}

abstract class ColumnExpressionWithTables {
  List<TableBuilder> get tables;
}

abstract class ColumnExpressionWithTablesMixin
    implements ColumnExpressionBuilderNode {
  List<TableBuilder> get tables {
    if (this is ColumnExpressionBuilder) {
      return [(this as ColumnExpressionBuilder).table];
    } else if (this is AbstractColumnExpressionCombiner) {
      final combiner = this as AbstractColumnExpressionCombiner;
      return combiner.lhs.tables..addAll(combiner.rhs.tables);
    } else {
      return []; //should assert here?
    }
  }
}

abstract class ExpressionMixin implements ColumnExpressionBuilderNode {
  ColumnExpressionBuilderORNode or(ColumnExpressionBuilderNode builder) =>
      ColumnExpressionBuilderORNode(this, builder);

  ColumnExpressionBuilderANDNode and(ColumnExpressionBuilderNode builder) =>
      ColumnExpressionBuilderANDNode(this, builder);
}

class ColumnExpressionBuilderORNode = AbstractColumnExpressionCombiner
    with
        ExpressionMixin,
        ColumnExpressionWithTablesMixin,
        ColumnExpressionWithPredicateMixin
    implements ColumnExpressionBuilderNode;

class ColumnExpressionBuilderANDNode = AbstractColumnExpressionCombiner
    with
        ExpressionMixin,
        ColumnExpressionWithTablesMixin,
        ColumnExpressionWithPredicateMixin
    implements ColumnExpressionBuilderNode;

class ColumnExpressionBuilderGroupORNode = AbstractColumnExpressionCombiner
    with
        ExpressionMixin,
        ColumnExpressionWithTablesMixin,
        ColumnExpressionWithPredicateMixin
    implements ColumnExpressionBuilderNode;

class ColumnExpressionBuilderGroupAndNode = AbstractColumnExpressionCombiner
    with
        ExpressionMixin,
        ColumnExpressionWithTablesMixin,
        ColumnExpressionWithPredicateMixin
    implements ColumnExpressionBuilderNode;

class ColumnExpressionBuilder extends ColumnBuilder with ExpressionMixin, ColumnExpressionWithTablesMixin, ColumnExpressionWithPredicateMixin implements ColumnExpressionBuilderNode {
  ColumnExpressionBuilder.property(TableBuilder table, this.expression, ManagedPropertyDescription property) :
      super.mixin(table, property);
  ColumnExpressionBuilder.keyPath(TableBuilder table, this.expression, KeyPath keyPath) :
        super.mixin(isOnJoinedTable(keyPath)
              ? _findJoinedTable(table, keyPath)
              : table,
          getProperty(keyPath)
      );

  static ColumnExpressionBuilderNode query(TableBuilder table,
      QueryExpression expression) {
    final predicateExpression = expression.expression;
    if (predicateExpression is AndExpression) {
      return ColumnExpressionBuilderANDNode(
          ColumnExpressionBuilder.query(table, predicateExpression.lhs),
          ColumnExpressionBuilder.query(table, predicateExpression.rhs)
      );
    } else if (predicateExpression is AndGroupExpression) {
        return ColumnExpressionBuilderGroupAndNode(
            ColumnExpressionBuilder.query(table, predicateExpression.lhs),
            ColumnExpressionBuilder.query(table, predicateExpression.rhs)
        );
    } else if (predicateExpression is OrExpression) {
      return ColumnExpressionBuilderORNode(
          ColumnExpressionBuilder.query(table, predicateExpression.lhs),
          ColumnExpressionBuilder.query(table, predicateExpression.rhs)
      );
    } else if (predicateExpression is OrGroupExpression) {
      return ColumnExpressionBuilderGroupORNode(
          ColumnExpressionBuilder.query(table, predicateExpression.lhs),
          ColumnExpressionBuilder.query(table, predicateExpression.rhs)
      );
    } else {
      return ColumnExpressionBuilder.keyPath(
          table, expression.expression, expression.keyPath);
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
