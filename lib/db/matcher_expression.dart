part of aqueduct;

// Still need string matchers, object master

enum MatcherOperator {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo,
  equalTo
}
dynamic whereEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.equalTo);
}
dynamic whereGreaterThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.greaterThan);
}
dynamic whereGreaterThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.greaterThanEqualTo);
}
dynamic whereLessThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.lessThan);
}
dynamic whereLessThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.lessThanEqualTo);
}
dynamic whereNotEqual(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.notEqual);
}

dynamic whereIn(Iterable<dynamic> values) {
  return new _WithinMatcherExpression(values.toList());
}

dynamic whereBetween(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, true);
}
dynamic whereOutsideOf(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, false);
}

dynamic whereRelatedByValue(dynamic foreignKeyValue) {
  return new _ComparisonMatcherExpression(foreignKeyValue, MatcherOperator.equalTo);
}

const dynamic whereNull = const _NullMatcherExpression(true);
const dynamic whereNotNull = const _NullMatcherExpression(false);
dynamic get whereAnyMatch => new _IncludeModelMatcherExpression();

abstract class MatcherExpression {
}

class _ComparisonMatcherExpression implements MatcherExpression {
  final dynamic value;
  final MatcherOperator operator;

  const _ComparisonMatcherExpression(this.value, this.operator);
}

class _RangeMatcherExpression implements MatcherExpression {
  final bool within;
  final dynamic lhs, rhs;
  const _RangeMatcherExpression(this.lhs, this.rhs, this.within);
}

class _NullMatcherExpression implements MatcherExpression {
  final bool shouldBeNull;
  const _NullMatcherExpression(this.shouldBeNull);
}

class _IncludeModelMatcherExpression implements MatcherExpression {
  _IncludeModelMatcherExpression();
}

class _WithinMatcherExpression implements MatcherExpression {
  List<dynamic> values;
  _WithinMatcherExpression(this.values);
}

class PredicateMatcherException implements Exception {
  String message;
  PredicateMatcherException(this.message);
}