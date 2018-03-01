import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/postgresql/mappers/column.dart';
import 'package:aqueduct/src/db/postgresql/mappers/table.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/query.dart';

class ExpressionMapper extends ColumnMapper {
  ExpressionMapper(EntityTableMapper table, ManagedPropertyDescription property, this.expression,
      {this.additionalVariablePrefix: ""})
      : super(table, property);

  String additionalVariablePrefix;
  PredicateExpression expression;

  String get defaultVariablePrefix => "$additionalVariablePrefix${table.tableReference}_";

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
    var name = columnName(withTableNamespace: true);
    var variableName = columnName(withPrefix: defaultVariablePrefix);

    return new QueryPredicate("$name ${ColumnMapper.symbolTable[operator]} @$variableName$typeSuffix",
        {variableName: convertValueForStorage(value)});
  }

  QueryPredicate containsPredicate(bool within, Iterable<dynamic> values) {
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "$defaultVariablePrefix${counter}_";

      var variableName = columnName(withPrefix: prefix);
      tokenList.add("@$variableName$typeSuffix");
      pairedMap[variableName] = convertValueForStorage(value);

      counter++;
    });

    var name = columnName(withTableNamespace: true);
    var keyword = within ? "IN" : "NOT IN";
    return new QueryPredicate("$name $keyword (${tokenList.join(",")})", pairedMap);
  }

  QueryPredicate nullPredicate(bool isNull) {
    var name = columnName(withTableNamespace: true);
    return new QueryPredicate("$name ${isNull ? "ISNULL" : "NOTNULL"}", {});
  }

  QueryPredicate rangePredicate(dynamic lhsValue, dynamic rhsValue, bool insideRange) {
    var name = columnName(withTableNamespace: true);
    var lhsName = columnName(withPrefix: "${defaultVariablePrefix}lhs_");
    var rhsName = columnName(withPrefix: "${defaultVariablePrefix}rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return new QueryPredicate("$name $operation @$lhsName$typeSuffix AND @$rhsName$typeSuffix",
        {lhsName: convertValueForStorage(lhsValue), rhsName: convertValueForStorage(rhsValue)});
  }

  QueryPredicate stringPredicate(
      PredicateStringOperator operator, dynamic value, bool caseSensitive, bool invertOperator) {
    var n = columnName(withTableNamespace: true);
    var variableName = columnName(withPrefix: defaultVariablePrefix);

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

    return new QueryPredicate("$n $operation @$variableName$typeSuffix", {variableName: matchValue});
  }
}

class SortMapper extends ColumnMapper {
  SortMapper(EntityTableMapper table, ManagedPropertyDescription property, QuerySortOrder order)
      : super(table, property) {
    this.order = (order == QuerySortOrder.ascending ? "ASC" : "DESC");
  }

  String order;

  String get orderByString => "${columnName(withTableNamespace: true)} $order";
}
