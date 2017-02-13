import 'matcher_internal.dart';
import 'query.dart';
import '../managed/managed.dart';

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
enum StringMatcherOperator { beginsWith, contains, endsWith }

/// Matcher for exactly matching a column value in a [Query].
///
/// See [Query.where]. Example:
///
///       var query = new Query<User>()
///         ..where.id = whereEqualTo(1);
T whereEqualTo<T>(T value) {
  return new ComparisonMatcherExpression(value, MatcherOperator.equalTo) as dynamic;
}

/// Matcher for matching a column value greater than the argument in a [Query].
///
/// See [Query.where]. Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereGreaterThan(60000);
T whereGreaterThan<T>(T value) {
  return new ComparisonMatcherExpression(value, MatcherOperator.greaterThan) as dynamic;
}

/// Matcher for matching a column value greater than or equal to the argument in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereGreaterThanEqualTo(60000);
T whereGreaterThanEqualTo<T>(dynamic value) {
  return new ComparisonMatcherExpression(
      value, MatcherOperator.greaterThanEqualTo) as dynamic;
}

/// Matcher for matching a column value less than the argument in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereLessThan(60000);
T whereLessThan<T>(T value) {
  return new ComparisonMatcherExpression(value, MatcherOperator.lessThan) as dynamic;
}

/// Matcher for matching a column value less than or equal to the argument in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereLessThanEqualTo(60000);
T whereLessThanEqualTo<T>(T value) {
  return new ComparisonMatcherExpression(
      value, MatcherOperator.lessThanEqualTo) as dynamic;
}

/// Matcher for matching all column values other than argument in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.id = whereNotEqual(60000);
T whereNotEqual<T>(T value) {
  return new ComparisonMatcherExpression(value, MatcherOperator.notEqual) as dynamic;
}

/// Matcher for matching string properties that contain [value] in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.title = whereContains("Director");
T whereContains<T extends String>(T value) {
  return new StringMatcherExpression(value, StringMatcherOperator.contains) as dynamic;
}

/// Matcher for matching string properties that start with [value] in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereBeginsWith("B");
T whereBeginsWith<T extends String>(T value) {
  return new StringMatcherExpression(value, StringMatcherOperator.beginsWith) as dynamic;
}

/// Matcher for matching string properties that end with [value] in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereEndsWith("son");
T whereEndsWith<T extends String>(T value) {
  return new StringMatcherExpression(value, StringMatcherOperator.endsWith) as dynamic;
}

/// Matcher for matching values that are within the list of [values] in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.department = whereIn(["Engineering", "HR"]);
T whereIn<T>(Iterable<T> values) {
  return new WithinMatcherExpression(values.toList()) as dynamic;
}

/// Matcher for matching column values where [lhs] <= value <= [rhs] in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereBetween(80000, 100000);
T whereBetween<T>(T lhs, T rhs) {
  return new RangeMatcherExpression(lhs, rhs, true) as dynamic;
}

/// Matcher for matching column values where matched value is less than [lhs] or greater than [rhs] in a [Query].
///
/// See [Query.where].  Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereOutsideOf(80000, 100000);
T whereOutsideOf<T>(T lhs, T rhs) {
  return new RangeMatcherExpression(lhs, rhs, false) as dynamic;
}

/// Matcher for matching [ManagedRelationship] property in a [Query].
///
/// This matcher can be assigned to a [ManagedRelationship] property. The underlying
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

/// Matcher for matching null in a [Query].
///
/// See [Query.where]. Example:
///
///       var q = new Query<Employee>()
///         ..where.manager = whereNull;
const dynamic whereNull = const NullMatcherExpression(true);

/// Matcher for matching everything but null in a [Query].
///
/// See [Query.where]. Example:
///
///       var q = new Query<Employee>()
///         ..where.manager = whereNotNull;
const dynamic whereNotNull = const NullMatcherExpression(false);

/// Thrown when a [Query] matcher is invalid.
class PredicateMatcherException implements Exception {
  PredicateMatcherException(this.message);

  String message;

  String toString() {
    return "PredicateMatcherException: $message";
  }
}
