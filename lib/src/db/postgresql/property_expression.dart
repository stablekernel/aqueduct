import 'property_mapper.dart';
import '../query/matcher_internal.dart';
import '../db.dart';

class PropertyExpression extends PropertyMapper {
  PropertyExpression(ManagedPropertyDescription property, this.expression)
      : super(property);

  String get name => property.name;
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
    var prefix = "${property.entity.tableName}_";
    var n = columnName(withTableNamespace: true);
    var variableName = columnName(withPrefix: prefix);

    return new QueryPredicate(
        "$n ${PropertyMapper.symbolTable[operator]} @$variableName${PropertyMapper.typeSuffixForProperty(property)}",
        {variableName: value});
  }

  QueryPredicate containsPredicate(Iterable<dynamic> values) {
    var tableName = property.entity.tableName;
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "ctns${tableName}_${counter}_";

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
    var n = columnName(withTableNamespace: true);
    var lhsName = columnName(withPrefix: "${property.entity.tableName}_lhs_");
    var rhsName = columnName(withPrefix: "${property.entity.tableName}_rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return new QueryPredicate(
        "$n $operation @$lhsName${PropertyMapper.typeSuffixForProperty(property)} AND @$rhsName${PropertyMapper.typeSuffixForProperty(property)}",
        {lhsName: lhsValue, rhsName: rhsValue});
  }

  QueryPredicate stringPredicate(StringMatcherOperator operator, dynamic value) {
    var prefix = "${property.entity.tableName}_";
    var n = columnName(withTableNamespace: true);
    var variableName = columnName(withPrefix: prefix);

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
