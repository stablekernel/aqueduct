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
  Predicate getPredicate(String prefix, String propertyName, int matcherIndex);
}

class _AssignmentMatcherExpression implements MatcherExpression {
  final dynamic value;
  const _AssignmentMatcherExpression(this.value);

  Predicate getPredicate(String prefix, String propertyName, int matcherIndex) {
    var formatSpecificationName = "${propertyName}_${matcherIndex}";
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

  Predicate getPredicate(String prefix, String propertyName, int matcherIndex) {
    var formatSpecificationName = "${propertyName}_${matcherIndex}";
    return new Predicate("$prefix.$propertyName ${symbolTable[operator]} @$formatSpecificationName",  {formatSpecificationName : value});
  }
}

class _RangeMatcherExpression implements MatcherExpression {
  final bool within;
  final dynamic lhs, rhs;
  const _RangeMatcherExpression(this.lhs, this.rhs, this.within);

  Predicate getPredicate(String prefix, String propertyName, int matcherIndex) {
    var lhsFormatSpecificationName = "${propertyName}_lhs${matcherIndex}";
    var rhsRormatSpecificationName = "${propertyName}_rhs${matcherIndex + 1}";
    return new Predicate("$prefix.$propertyName ${within ? "between" : "not between"} @$lhsFormatSpecificationName and @$rhsRormatSpecificationName",
        {lhsFormatSpecificationName: lhs, rhsRormatSpecificationName : rhs});
  }
}

class _NullMatcherExpression implements MatcherExpression {
  final bool shouldBeNull;
  const _NullMatcherExpression(this.shouldBeNull);

  Predicate getPredicate(String prefix, String propertyName, int matcherIndex) {
    return new Predicate("$prefix.$propertyName ${shouldBeNull ? "isnull" : "notnull"}", {});
  }
}

class _BelongsToModelMatcherExpression implements MatcherExpression {
  final dynamic value;

  _BelongsToModelMatcherExpression(this.value);

  Predicate getPredicate(String prefix, String propertyName, int matcherIndex) {
    var formatSpecificationName = "${propertyName}_${matcherIndex}";
    return new Predicate("$prefix.$propertyName = @$formatSpecificationName", {formatSpecificationName : value});
  }
}

class _IncludeModelMatcherExpression implements MatcherExpression {
  _IncludeModelMatcherExpression();
  Predicate getPredicate(String prefix, String propertyName, int matcherIndex) {
    return null;
  }
}

class PredicateMatcherException {
  String message;
  PredicateMatcherException(this.message);
}