import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/query.dart';

class ColumnExpressionBuilder extends ColumnBuilder {
  ColumnExpressionBuilder(TableBuilder table, ManagedPropertyDescription property, this.expression,
      {this.prefix: ""})
      : super(table, property);

  final String prefix;
  PredicateExpression expression;

  String get defaultPrefix => "$prefix${table.sqlTableReference}_";

  QueryPredicate get predicate {
    var expr = expression;
    if (expr is ComparisonExpression) {
      return comparisonPredicate(expr.operator, expr.value);
    } else if (expr is RangeExpression) {
      return rangePredicate(expr.lhs, expr.rhs, expr.within);
    } else if (expr is NullCheckExpression) {
      return nullPredicate(expr.shouldBeNull);
    } else if (expr is SetMembershipExpression) {
      return containsPredicate(expr.within, expr.values);
    } else if (expr is StringExpression) {
      return stringPredicate(expr.operator, expr.value, expr.caseSensitive, expr.invertOperator);
    }

    throw new UnsupportedError(
        "Unknown expression applied to 'Query'. '${expr.runtimeType}' is not supported by 'PostgreSQL'.");
  }

  QueryPredicate comparisonPredicate(PredicateOperator operator, dynamic value) {
    var name = sqlColumnName(withTableNamespace: true);
    var variableName = sqlColumnName(withPrefix: defaultPrefix);

    return new QueryPredicate("$name ${ColumnBuilder.symbolTable[operator]} @$variableName$sqlTypeSuffix",
        {variableName: convertValueForStorage(value)});
  }

  QueryPredicate containsPredicate(bool within, Iterable<dynamic> values) {
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
    return new QueryPredicate("$name $keyword (${tokenList.join(",")})", pairedMap);
  }

  QueryPredicate nullPredicate(bool isNull) {
    var name = sqlColumnName(withTableNamespace: true);
    return new QueryPredicate("$name ${isNull ? "ISNULL" : "NOTNULL"}", {});
  }

  QueryPredicate rangePredicate(dynamic lhsValue, dynamic rhsValue, bool insideRange) {
    var name = sqlColumnName(withTableNamespace: true);
    var lhsName = sqlColumnName(withPrefix: "${defaultPrefix}lhs_");
    var rhsName = sqlColumnName(withPrefix: "${defaultPrefix}rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return new QueryPredicate("$name $operation @$lhsName$sqlTypeSuffix AND @$rhsName$sqlTypeSuffix",
        {lhsName: convertValueForStorage(lhsValue), rhsName: convertValueForStorage(rhsValue)});
  }

  QueryPredicate stringPredicate(
      PredicateStringOperator operator, dynamic value, bool caseSensitive, bool invertOperator) {
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

    return new QueryPredicate("$n $operation @$variableName$sqlTypeSuffix", {variableName: matchValue});
  }
}