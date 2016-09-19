part of aqueduct;

/// The operator in a comparison matcher.
enum MatcherOperator {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo,
  equalTo
}

enum StringMatcherOperator {
  beginsWith, contains, endsWith
}

/// Matcher for exactly matching a value in a [Query].
dynamic whereEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.equalTo);
}

/// Matcher for matching a value greater than the argument in a [Query].
dynamic whereGreaterThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.greaterThan);
}

/// Matcher for matching a value greater than or equal to the argument in a [Query].
dynamic whereGreaterThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.greaterThanEqualTo);
}

/// Matcher for matching a value less than the argument in a [Query].
dynamic whereLessThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.lessThan);
}

/// Matcher for matching a value less than or equal to the argument in a [Query].
dynamic whereLessThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.lessThanEqualTo);
}

/// Matcher for matching all values other than argument in a [Query].
dynamic whereNotEqual(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.notEqual);
}

/// Matcher for matching string properties that contain [value] in a [Query].
dynamic whereContains(String value) {
  return new _StringMatcherExpression(value, StringMatcherOperator.contains);
}

/// Matcher for matching string properties that start with [value] in a [Query].
dynamic whereBeginsWith(String value) {
  return new _StringMatcherExpression(value, StringMatcherOperator.beginsWith);
}

/// Matcher for matching string properties that end with [value] in a [Query].
dynamic whereEndsWith(String value) {
  return new _StringMatcherExpression(value, StringMatcherOperator.endsWith);
}

/// Matcher for matching values that are within the list of [values] in a [Query].
dynamic whereIn(Iterable<dynamic> values) {
  return new _WithinMatcherExpression(values.toList());
}

/// Matcher for matching values where [lhs] <= value <= [rhs] in a [Query].
dynamic whereBetween(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, true);
}

/// Matcher for matching values where matched value is less than [lhs] or greater than [rhs] in a [Query].
dynamic whereOutsideOf(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, false);
}

/// Matcher for matching belongs to relationships in a [Query].
///
/// Example:
///
///       var modelQuery = new ModelQuery<SomethingUserHas>()
///         ..user = whereRelatedByValue(userPrimaryKey);
///
dynamic whereRelatedByValue(dynamic foreignKeyValue) {
  return new _ComparisonMatcherExpression(foreignKeyValue, MatcherOperator.equalTo);
}

/// Matcher for matching null in a [Query].
const dynamic whereNull = const _NullMatcherExpression(true);

/// Matcher for matching everything but null in a [Query].
const dynamic whereNotNull = const _NullMatcherExpression(false);

abstract class MatcherExpression {}

class _ComparisonMatcherExpression implements MatcherExpression {
  const _ComparisonMatcherExpression(this.value, this.operator);

  final dynamic value;
  final MatcherOperator operator;
}

class _RangeMatcherExpression implements MatcherExpression {
  const _RangeMatcherExpression(this.lhs, this.rhs, this.within);

  final bool within;
  final dynamic lhs, rhs;
}

class _NullMatcherExpression implements MatcherExpression {
  const _NullMatcherExpression(this.shouldBeNull);

  final bool shouldBeNull;
}

class _WithinMatcherExpression implements MatcherExpression {
  _WithinMatcherExpression(this.values);

  List<dynamic> values;
}

class _StringMatcherExpression implements MatcherExpression {
  _StringMatcherExpression(this.value, this.operator);

  StringMatcherOperator operator;
  String value;
}

/// Thrown when a matcher is invalid.
class PredicateMatcherException implements Exception {
  PredicateMatcherException(this.message);

  String message;

  String toString() {
    return "PredicateMatcherException: $message";
  }
}