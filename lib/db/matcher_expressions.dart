part of monadart;

enum _MatcherOperator {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo,
 // between
}

abstract class MatcherExpression {
  Predicate getPredicate(String propertyName, int matcherIndex);
}

class _AssignmentMatcherExpression implements MatcherExpression {
  final dynamic value;
  _AssignmentMatcherExpression(this.value);

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

  _ComparisonMatcherExpression(this.value, this.operator);

  Predicate getPredicate(String propertyName, int matcherIndex) {
    var formatSpecificationName = "${propertyName}_${matcherIndex}";
    return new Predicate("$propertyName ${symbolTable[operator]} @$formatSpecificationName",  {formatSpecificationName : value});
  }
}

class PredicateMatcherException {
  String message;
  PredicateMatcherException(this.message);
}