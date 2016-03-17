part of monadart;

// Still need string matchers, object master

enum _MatcherOperator {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo
}
dynamic whereEqualTo(dynamic value) {
  return new _AssignmentMatcherExpression(value);
}
dynamic whereIn(Iterable<dynamic> values) {
  return new _WithinMatcherExpression(values);
}
dynamic whereGreaterThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.greaterThan);
}
dynamic whereGreaterThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.greaterThanEqualTo);
}
dynamic whereLessThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.lessThan);
}
dynamic whereLessThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.lessThanEqualTo);
}
dynamic whereNotEqual(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.notEqual);
}

dynamic whereBetween(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, true);
}
dynamic whereOutsideOf(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, false);
}

dynamic whereRelatedByValue(dynamic foreignKeyValue) {
  return new _BelongsToModelMatcherExpression(foreignKeyValue);
}

dynamic whereMatching(ModelQuery expr) {
  return expr;
}

const dynamic whereNull = const _NullMatcherExpression(true);
const dynamic whereNotNull = const _NullMatcherExpression(false);
dynamic get whereAnyMatch => new _IncludeModelMatcherExpression();

abstract class MatcherExpression {
  Predicate getPredicate(String prefix, String propertyName);
}

class _AssignmentMatcherExpression implements MatcherExpression {
  final dynamic value;
  const _AssignmentMatcherExpression(this.value);

  Predicate getPredicate(String prefix, String propertyName) {
    var formatSpecificationName = "${propertyName}";
    return new Predicate("$prefix.$propertyName = @$formatSpecificationName",  {formatSpecificationName : value});
  }
}

class _ComparisonMatcherExpression implements MatcherExpression {
  static Map<_MatcherOperator, String> symbolTable = {
    _MatcherOperator.lessThan : "<",
    _MatcherOperator.greaterThan : ">",
    _MatcherOperator.notEqual : "!=",
    _MatcherOperator.lessThanEqualTo : "<=",
    _MatcherOperator.greaterThanEqualTo : ">="
  };

  final dynamic value;
  final _MatcherOperator operator;

  const _ComparisonMatcherExpression(this.value, this.operator);

  Predicate getPredicate(String prefix, String propertyName) {
    var formatSpecificationName = "${propertyName}";
    return new Predicate("$prefix.$propertyName ${symbolTable[operator]} @$formatSpecificationName",  {formatSpecificationName : value});
  }
}

class _RangeMatcherExpression implements MatcherExpression {
  final bool within;
  final dynamic lhs, rhs;
  const _RangeMatcherExpression(this.lhs, this.rhs, this.within);

  Predicate getPredicate(String prefix, String propertyName) {
    var lhsFormatSpecificationName = "${propertyName}_lhs";
    var rhsRormatSpecificationName = "${propertyName}_rhs";
    return new Predicate("$prefix.$propertyName ${within ? "between" : "not between"} @$lhsFormatSpecificationName and @$rhsRormatSpecificationName",
        {lhsFormatSpecificationName: lhs, rhsRormatSpecificationName : rhs});
  }
}

class _NullMatcherExpression implements MatcherExpression {
  final bool shouldBeNull;
  const _NullMatcherExpression(this.shouldBeNull);

  Predicate getPredicate(String prefix, String propertyName) {
    return new Predicate("$prefix.$propertyName ${shouldBeNull ? "isnull" : "notnull"}", {});
  }
}

class _BelongsToModelMatcherExpression implements MatcherExpression {
  final dynamic value;

  _BelongsToModelMatcherExpression(this.value);

  Predicate getPredicate(String prefix, String propertyName) {
    var formatSpecificationName = "${propertyName}";
    return new Predicate("$prefix.$propertyName = @$formatSpecificationName", {formatSpecificationName : value});
  }
}

class _IncludeModelMatcherExpression implements MatcherExpression {
  _IncludeModelMatcherExpression();
  Predicate getPredicate(String prefix, String propertyName) {
    return null;
  }
}

class _WithinMatcherExpression implements MatcherExpression {
  List<dynamic> values;
  _WithinMatcherExpression(this.values);

  Predicate getPredicate(String prefix, String propertyName) {
    var tokenList = [];
    var pairedMap = {};
    for (var i = 0; i < values.length; i++) {
      var token = "wme$prefix${propertyName}_$i";
      tokenList.add("@$token");
      pairedMap[token] = values[i];
    }

    return new Predicate("$prefix.$propertyName in (${tokenList.join(",")})", pairedMap);
  }

}


class PredicateMatcherException {
  String message;
  PredicateMatcherException(this.message);
}