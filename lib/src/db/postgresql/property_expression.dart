import 'property_mapper.dart';
import '../query/matcher_internal.dart';
import '../db.dart';
import 'entity_table.dart';

class PropertyExpression extends PropertyMapper {
  PropertyExpression(EntityTableMapper table, ManagedPropertyDescription property, this.expression, {this.additionalVariablePrefix: ""})
      : super(table, property);

  String additionalVariablePrefix;
  MatcherExpression expression;

  QueryPredicate get predicate {
    var expr = expression;
    if (expr is ComparisonMatcherExpression) {
      return comparisonPredicate(expr.operator, expr.value);
    } else if (expr is RangeMatcherExpression) {
      return rangePredicate(expr.lhs, expr.rhs, expr.within);
    } else if (expr is NullMatcherExpression) {
      return nullPredicate(expr.shouldBeNull);
    } else if (expr is WithinMatcherExpression) {
      return containsPredicate(expr.values);
    } else if (expr is StringMatcherExpression) {
      return stringPredicate(expr.operator, expr.value);
    }

    throw new QueryPredicateException(
        "Unknown MatcherExpression ${expr.runtimeType}");
  }

  QueryPredicate comparisonPredicate(MatcherOperator operator, dynamic value) {
    var n = columnName(withTableNamespace: true);
    var variableName = columnName(withPrefix: "$additionalVariablePrefix${table.tableReference}_");

    return new QueryPredicate(
        "$n ${PropertyMapper.symbolTable[operator]} @$variableName${PropertyMapper.typeSuffixForProperty(property)}",
        {variableName: value});
  }

  QueryPredicate containsPredicate(Iterable<dynamic> values) {
    var globalNamespacePrefix = "$additionalVariablePrefix${table.tableReference}";
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "${globalNamespacePrefix}_${counter}_";

      var variableName = columnName(withPrefix: prefix);
      tokenList.add("@$variableName${PropertyMapper.typeSuffixForProperty(property)}");
      pairedMap[variableName] = value;

      counter++;
    });

    var n = columnName(withTableNamespace: true);
    return new QueryPredicate(
        "$n IN (${tokenList.join(",")})", pairedMap);
  }

  QueryPredicate nullPredicate(bool isNull) {
    var n = columnName(withTableNamespace: true);
    return new QueryPredicate(
        "$n ${isNull ? "ISNULL" : "NOTNULL"}", {});
  }

  QueryPredicate rangePredicate(dynamic lhsValue, dynamic rhsValue, bool insideRange) {
    var globalNamespacePrefix = "$additionalVariablePrefix${table.tableReference}";

    var n = columnName(withTableNamespace: true);
    var lhsName = columnName(withPrefix: "${globalNamespacePrefix}_lhs_");
    var rhsName = columnName(withPrefix: "${globalNamespacePrefix}_rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return new QueryPredicate(
        "$n $operation @$lhsName${PropertyMapper.typeSuffixForProperty(property)} AND @$rhsName${PropertyMapper.typeSuffixForProperty(property)}",
        {lhsName: lhsValue, rhsName: rhsValue});
  }

  QueryPredicate stringPredicate(StringMatcherOperator operator, dynamic value) {
    var n = columnName(withTableNamespace: true);
    var variableName = columnName(withPrefix: "$additionalVariablePrefix${table.tableReference}_");

    var matchValue = value;
    switch (operator) {
      case StringMatcherOperator.beginsWith:
        matchValue = "$value%";
        break;
      case StringMatcherOperator.endsWith:
        matchValue = "%$value";
        break;
      case StringMatcherOperator.contains:
        matchValue = "%$value%";
        break;
    }

    return new QueryPredicate(
        "$n LIKE @$variableName${PropertyMapper.typeSuffixForProperty(property)}",
        {variableName: matchValue});
  }
}

class PropertySortMapper extends PropertyMapper {
  PropertySortMapper(EntityTableMapper table, ManagedPropertyDescription property, QuerySortOrder order)
      : super(table, property) {
    this.order = (order == QuerySortOrder.ascending ? "ASC" : "DESC");
  }

  String order;

  String get orderByString =>
    "${columnName(withTableNamespace: true)} $order";
}