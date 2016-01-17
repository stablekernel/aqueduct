part of monadart;

enum _MatcherOperator {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo
}
dynamic whenEqualTo(dynamic value) {
  return new _AssignmentMatcherExpression(value);
}

dynamic whenGreaterThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.greaterThan);
}
dynamic whenGreaterThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.greaterThanEqualTo);
}
dynamic whenLessThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.lessThan);
}
dynamic whenLessThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.lessThanEqualTo);
}
dynamic whenNotEqual(dynamic value) {
  return new _ComparisonMatcherExpression(value, _MatcherOperator.notEqual);
}

dynamic whenBetween(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, true);
}
dynamic whenOutsideOf(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, false);
}

const dynamic whenNull = const _NullMatcherExpression(true);
const dynamic whenNotNull = const _NullMatcherExpression(false);


abstract class MatcherExpression {
  Predicate getPredicate(String propertyName, int matcherIndex);
}

class _AssignmentMatcherExpression implements MatcherExpression {
  final dynamic value;
  const _AssignmentMatcherExpression(this.value);

  Predicate getPredicate(String propertyName, int matcherIndex) {
    var formatSpecificationName = "${propertyName}_${matcherIndex}";
    return new Predicate("$propertyName = @$formatSpecificationName",  {formatSpecificationName : value});
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

  Predicate getPredicate(String propertyName, int matcherIndex) {
    var formatSpecificationName = "${propertyName}_${matcherIndex}";
    return new Predicate("$propertyName ${symbolTable[operator]} @$formatSpecificationName",  {formatSpecificationName : value});
  }
}

class _RangeMatcherExpression implements MatcherExpression {
  final bool within;
  final dynamic lhs, rhs;
  const _RangeMatcherExpression(this.lhs, this.rhs, this.within);

  Predicate getPredicate(String propertyName, int matcherIndex) {
    var lhsFormatSpecificationName = "${propertyName}_lhs${matcherIndex}";
    var rhsRormatSpecificationName = "${propertyName}_rhs${matcherIndex}";
    return new Predicate("$propertyName ${within ? "between" : "not between"} @$lhsFormatSpecificationName and @$rhsRormatSpecificationName",
        {lhsFormatSpecificationName: lhs, rhsRormatSpecificationName : rhs});
  }
}

class _NullMatcherExpression implements MatcherExpression {
  final bool shouldBeNull;
  const _NullMatcherExpression(this.shouldBeNull);

  Predicate getPredicate(String propertyName, int matcherIndex) {
    var formatSpecificationName = "${propertyName}_${matcherIndex}";
    return new Predicate("$propertyName ${shouldBeNull ? "isnull" : "notnull"}", {});
  }
}


class PredicateMatcherException {
  String message;
  PredicateMatcherException(this.message);
}