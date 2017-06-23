import '../db.dart';
import '../query/matcher_internal.dart';
import 'entity_table.dart';
import 'property_mapper.dart';

class PropertyExpression extends PropertyMapper {
  PropertyExpression(EntityTableMapper table,
      ManagedPropertyDescription property, this.expression,
      {this.additionalVariablePrefix: ""})
      : super(table, property);

  String additionalVariablePrefix;
  MatcherExpression expression;
  String get defaultVariablePrefix =>
      "$additionalVariablePrefix${table.tableReference}_";

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
      return stringPredicate(expr.operator, expr.value, expr.caseSensitive, expr.invertOperator);
    }

    throw new QueryPredicateException(
        "Unknown MatcherExpression ${expr.runtimeType}");
  }

  QueryPredicate comparisonPredicate(MatcherOperator operator, dynamic value) {
    var name = columnName(withTableNamespace: true);
    var variableName = columnName(withPrefix: defaultVariablePrefix);

    return new QueryPredicate(
        "$name ${PropertyMapper.symbolTable[operator]} @$variableName$typeSuffix",
        {variableName: _encodedValue(value)});
  }

  QueryPredicate containsPredicate(Iterable<dynamic> values) {
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "$defaultVariablePrefix${counter}_";

      var variableName = columnName(withPrefix: prefix);
      tokenList.add("@$variableName$typeSuffix");
      pairedMap[variableName] = _encodedValue(value);

      counter++;
    });

    var name = columnName(withTableNamespace: true);
    return new QueryPredicate("$name IN (${tokenList.join(",")})", pairedMap);
  }

  QueryPredicate nullPredicate(bool isNull) {
    var name = columnName(withTableNamespace: true);
    return new QueryPredicate("$name ${isNull ? "ISNULL" : "NOTNULL"}", {});
  }

  QueryPredicate rangePredicate(
      dynamic lhsValue, dynamic rhsValue, bool insideRange) {
    var name = columnName(withTableNamespace: true);
    var lhsName = columnName(withPrefix: "${defaultVariablePrefix}lhs_");
    var rhsName = columnName(withPrefix: "${defaultVariablePrefix}rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return new QueryPredicate(
        "$name $operation @$lhsName$typeSuffix AND @$rhsName$typeSuffix",
        {lhsName: _encodedValue(lhsValue), rhsName: _encodedValue(rhsValue)});
  }

  QueryPredicate stringPredicate(
      StringMatcherOperator operator, dynamic value, bool caseSensitive, bool invertOperator) {
    var n = columnName(withTableNamespace: true);
    var variableName = columnName(withPrefix: defaultVariablePrefix);

    var matchValue = value;
    var operation = caseSensitive ? "LIKE" : "ILIKE";
    if (invertOperator) {
      operation = "NOT $operation";
    }
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
      default: break;
    }

    return new QueryPredicate(
        "$n $operation @$variableName$typeSuffix", {variableName: matchValue});
  }

  dynamic _encodedValue(dynamic value) {
    if (property is ManagedAttributeDescription) {
      if ((property as ManagedAttributeDescription).isEnumeratedValue) {
        return property.encodeValue(value);
      }
    }

    return value;
  }
}

class PropertySortMapper extends PropertyMapper {
  PropertySortMapper(EntityTableMapper table,
      ManagedPropertyDescription property, QuerySortOrder order)
      : super(table, property) {
    this.order = (order == QuerySortOrder.ascending ? "ASC" : "DESC");
  }

  String order;

  String get orderByString => "${columnName(withTableNamespace: true)} $order";
}
