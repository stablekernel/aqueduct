import 'matcher_internal.dart';
import 'query.dart';
import '../persistent_store/persistent_store.dart';
import '../managed/managed.dart';

/// Matcher for exactly matching a column value when using [Query.where].
///
/// See [Query.where]. Example:
///
///       var query = new Query<User>()
///         ..where.id = whereEqualTo(1);
///
/// If matching a [String] value, [caseSensitive] is will toggle
/// if [value] is to be case sensitive equal to matched values.
/// Otherwise, this flag is ignored.
dynamic whereEqualTo(dynamic value, {bool caseSensitive: true}) {
  if (value is String) {
    return new StringMatcherExpression(
        value, StringMatcherOperator.equals, caseSensitive: caseSensitive);
  }
  return new ComparisonMatcherExpression(value, MatcherOperator.equalTo);
}

/// Matcher for matching all column values other than argument when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.id = whereNotEqual(60000);
///
/// If matching a [String] value, [caseSensitive] is will toggle
/// if [value] is to be case sensitive equal to matched values.
/// Otherwise, this flag is ignored.
dynamic whereNotEqualTo(dynamic value, {bool caseSensitive: true}) {
  if (value is String) {
    return new StringMatcherExpression(
        value, StringMatcherOperator.equals,
        caseSensitive: caseSensitive,
        invertOperator: true);
  }
  return new ComparisonMatcherExpression(value, MatcherOperator.notEqual);
}


/// Matcher for matching a column value greater than the argument when using [Query.where].
///
/// See [Query.where]. Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereGreaterThan(60000);
dynamic whereGreaterThan(dynamic value) {
  return new ComparisonMatcherExpression(value, MatcherOperator.greaterThan);
}

/// Matcher for matching a column value greater than or equal to the argument when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereGreaterThanEqualTo(60000);
dynamic whereGreaterThanEqualTo(dynamic value) {
  return new ComparisonMatcherExpression(
      value, MatcherOperator.greaterThanEqualTo);
}

/// Matcher for matching a column value less than the argument when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereLessThan(60000);
dynamic whereLessThan(dynamic value) {
  return new ComparisonMatcherExpression(value, MatcherOperator.lessThan);
}

/// Matcher for matching a column value less than or equal to the argument when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereLessThanEqualTo(60000);
dynamic whereLessThanEqualTo(dynamic value) {
  return new ComparisonMatcherExpression(
      value, MatcherOperator.lessThanEqualTo);
}

/// Matcher for matching string properties that contain [value] when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.title = whereContains("Director");
///
/// [caseSensitive] is will toggle
/// if [value] is to be case sensitive equal to matched values.
dynamic whereContainsString(String value, {bool caseSensitive: true}) {
  return new StringMatcherExpression(value, StringMatcherOperator.contains, caseSensitive: caseSensitive);
}

/// Matcher for matching string properties that start with [value] when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereBeginsWith("B");
///
/// [caseSensitive] is will toggle
/// if [value] is to be case sensitive equal to matched values.
dynamic whereBeginsWith(String value, {bool caseSensitive: true}) {
  return new StringMatcherExpression(value, StringMatcherOperator.beginsWith, caseSensitive: caseSensitive);
}

/// Matcher for matching string properties that do not end with [value] when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereDoesNotEndWith("son");
///
/// [caseSensitive] is will toggle
/// if [value] is to be case sensitive equal to matched values.
dynamic whereDoesNotEndWith(String value, {bool caseSensitive: true}) {
  return new StringMatcherExpression(
      value, StringMatcherOperator.endsWith,
      caseSensitive: caseSensitive,
      invertOperator: true);
}

/// Matcher for matching string properties that do not contain [value] when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.title = whereDoesNotContain("Director");
///
/// [caseSensitive] is will toggle
/// if [value] is to be case sensitive equal to matched values.
dynamic whereDoesNotContain(String value, {bool caseSensitive: true}) {
  return new StringMatcherExpression(
      value, StringMatcherOperator.contains,
      caseSensitive: caseSensitive,
      invertOperator: true);
}

/// Matcher for matching string properties that do not start with [value] when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereDoesNotBeginWith("B");
///
/// [caseSensitive] is will toggle
/// if [value] is to be case sensitive equal to matched values.
dynamic whereDoesNotBeginWith(String value, {bool caseSensitive: true}) {
  return new StringMatcherExpression(
      value, StringMatcherOperator.beginsWith,
      caseSensitive: caseSensitive,
      invertOperator: true);
}

/// Matcher for matching string properties that end with [value] when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereEndsWith("son");
///
/// [caseSensitive] is will toggle
/// if [value] is to be case sensitive equal to matched values.
dynamic whereEndsWith(String value, {bool caseSensitive: true}) {
  return new StringMatcherExpression(value, StringMatcherOperator.endsWith, caseSensitive: caseSensitive);
}

/// Matcher for matching values that are within the list of [values] when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.department = whereIn(["Engineering", "HR"]);
dynamic whereIn(Iterable<dynamic> values) {
  return new SetMembershipMatcherExpression(values.toList());
}

/// Matcher for matching column values where [lhs] <= value <= [rhs] when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereBetween(80000, 100000);
dynamic whereBetween(dynamic lhs, dynamic rhs) {
  return new RangeMatcherExpression(lhs, rhs, true);
}

/// Matcher for matching column values where matched value is less than [lhs] or greater than [rhs] when using [Query.where].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereOutsideOf(80000, 100000);
dynamic whereOutsideOf(dynamic lhs, dynamic rhs) {
  return new RangeMatcherExpression(lhs, rhs, false);
}

/// Matcher for matching [Relationship] property when using [Query.where].
///
/// This matcher can be assigned to a [Relationship] property. The underlying
/// [PersistentStore] will determine the name of the foreign key column to build
/// the query. See [Query.where].
///
/// Example:
///
///       var q = new Query<SomethingUserHas>()
///         ..where.user = whereRelatedByValue(userPrimaryKey);
dynamic whereRelatedByValue(dynamic foreignKeyValue) {
  return new ComparisonMatcherExpression(
      foreignKeyValue, MatcherOperator.equalTo);
}

/// Inverts a [Query.where] matcher.
///
/// Creates a matcher that inverts [expression]. For whatever results would be filtered
/// by [expression], the inverted expression both:
///
/// - includes the results that would have been excluded
/// - excludes the results that would have been included
///
/// For example, the following find's all users not named 'Bob'.
///
///       var q = new Query<User>()
///         ..where.name = whereNot(whereEqualTo("Bob"));
///
/// Note: null values are not evaluated. In the previous example, if name
/// were 'null' for some user, it would *not* be returned by the query.
///
dynamic whereNot(MatcherExpression expression) {
  return expression.inverse;
}

/// Matcher for matching null value when using [Query.where].
///
/// See [Query.where]. Example:
///
///       var q = new Query<Employee>()
///         ..where.manager = whereNull;
const dynamic whereNull = const NullMatcherExpression(true);

/// Matcher for matching everything but null when using [Query.where].
///
/// See [Query.where]. Example:
///
///       var q = new Query<Employee>()
///         ..where.manager = whereNotNull;
const dynamic whereNotNull = const NullMatcherExpression(false);
