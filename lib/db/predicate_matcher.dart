part of monadart;


enum MatcherOperator {
  lessThan,
  greaterThan,
  equal,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo,
  between
}

abstract class ModelMatcher<T extends Model> {
  List<MatcherExpression> matchers;
  // submatcher tree with or/and
}

abstract class MatcherExpression {
  Predicate get predicate;
}

abstract class _OrderingMatcher {
  num value;
  num otherValue;
  MatcherOperator operator;
}