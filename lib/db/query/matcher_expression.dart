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

/// The operator in a string matcher.
enum StringMatcherOperator {
  beginsWith, contains, endsWith
}

/// Matcher for exactly matching a column value in a [Query].
///
/// See [Query.matchOn]. Example:
///
///       var query = new Query<User>()
///         ..matchOn.id = whereEqualTo(1);
dynamic whereEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.equalTo);
}

/// Matcher for matching a column value greater than the argument in a [Query].
///
/// See [Query.matchOn]. Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.salary = whereGreaterThan(60000);
dynamic whereGreaterThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.greaterThan);
}

/// Matcher for matching a column value greater than or equal to the argument in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.salary = whereGreaterThanEqualTo(60000);
dynamic whereGreaterThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.greaterThanEqualTo);
}

/// Matcher for matching a column value less than the argument in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.salary = whereLessThan(60000);
dynamic whereLessThan(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.lessThan);
}

/// Matcher for matching a column value less than or equal to the argument in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.salary = whereLessThanEqualTo(60000);
dynamic whereLessThanEqualTo(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.lessThanEqualTo);
}

/// Matcher for matching all column values other than argument in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.id = whereNotEqual(60000);
dynamic whereNotEqual(dynamic value) {
  return new _ComparisonMatcherExpression(value, MatcherOperator.notEqual);
}

/// Matcher for matching string properties that contain [value] in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.title = whereContains("Director");
dynamic whereContains(String value) {
  return new _StringMatcherExpression(value, StringMatcherOperator.contains);
}

/// Matcher for matching string properties that start with [value] in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.name = whereBeginsWith("B");
dynamic whereBeginsWith(String value) {
  return new _StringMatcherExpression(value, StringMatcherOperator.beginsWith);
}

/// Matcher for matching string properties that end with [value] in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.name = whereEndsWith("son");
dynamic whereEndsWith(String value) {
  return new _StringMatcherExpression(value, StringMatcherOperator.endsWith);
}

/// Matcher for matching values that are within the list of [values] in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.department = whereIn(["Engineering", "HR"]);
dynamic whereIn(Iterable<dynamic> values) {
  return new _WithinMatcherExpression(values.toList());
}

/// Matcher for matching column values where [lhs] <= value <= [rhs] in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.salary = whereBetween(80000, 100000);
dynamic whereBetween(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, true);
}

/// Matcher for matching column values where matched value is less than [lhs] or greater than [rhs] in a [Query].
///
/// See [Query.matchOn].  Example:
///
///       var query = new Query<Employee>()
///         ..matchOn.salary = whereOutsideOf(80000, 100000);
dynamic whereOutsideOf(dynamic lhs, dynamic rhs) {
  return new _RangeMatcherExpression(lhs, rhs, false);
}

/// Matcher for matching [ManagedRelationship] property in a [Query].
///
/// This matcher can be assigned to a [ManagedRelationship] property. The underlying
/// [PersistentStore] will determine the name of the foreign key column to build
/// the query. See [Query.matchOn].
///
/// Example:
///
///       var q = new Query<SomethingUserHas>()
///         ..matchOn.user = whereRelatedByValue(userPrimaryKey);
dynamic whereRelatedByValue(dynamic foreignKeyValue) {
  return new _ComparisonMatcherExpression(foreignKeyValue, MatcherOperator.equalTo);
}

/// Matcher for matching null in a [Query].
///
/// See [Query.matchOn]. Example:
///
///       var q = new Query<Employee>()
///         ..matchOn.manager = whereNull;
const dynamic whereNull = const _NullMatcherExpression(true);

/// Matcher for matching everything but null in a [Query].
///
/// See [Query.matchOn]. Example:
///
///       var q = new Query<Employee>()
///         ..matchOn.manager = whereNotNull;
const dynamic whereNotNull = const _NullMatcherExpression(false);

abstract class _MatcherExpression {}

class _ComparisonMatcherExpression implements _MatcherExpression {
  const _ComparisonMatcherExpression(this.value, this.operator);

  final dynamic value;
  final MatcherOperator operator;
}

class _RangeMatcherExpression implements _MatcherExpression {
  const _RangeMatcherExpression(this.lhs, this.rhs, this.within);

  final bool within;
  final dynamic lhs, rhs;
}

class _NullMatcherExpression implements _MatcherExpression {
  const _NullMatcherExpression(this.shouldBeNull);

  final bool shouldBeNull;
}

class _WithinMatcherExpression implements _MatcherExpression {
  _WithinMatcherExpression(this.values);

  List<dynamic> values;
}

class _StringMatcherExpression implements _MatcherExpression {
  _StringMatcherExpression(this.value, this.operator);

  StringMatcherOperator operator;
  String value;
}

/// Thrown when a [Query] matcher is invalid.
class PredicateMatcherException implements Exception {
  PredicateMatcherException(this.message);

  String message;

  String toString() {
    return "PredicateMatcherException: $message";
  }
}