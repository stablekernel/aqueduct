import 'matcher_internal.dart';
import 'query.dart';
import '../managed/managed.dart';

/// Query matcher that tests that a column is equal to [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is equal to [value] are returned. [value] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [int], [String], [bool], [double] and [DateTime] types.
///
/// If [value] is [String], the flag [caseSensitive] controls whether or not equality is case-sensitively compared.
///
/// Example:
///
///       final query = new Query<User>()
///         ..where.id = whereEqualTo(1);
///
dynamic whereEqualTo(dynamic value, {bool caseSensitive: true}) {
  if (value is String) {
    return new StringExpression(
        value, PredicateStringOperator.equals, caseSensitive: caseSensitive);
  }
  return new ComparisonExpression(value, PredicateOperator.equalTo);
}

/// Query matcher that tests that a column is not equal to [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is *not equal* to [value] are returned. [value] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [int], [String], [bool], [double] and [DateTime] types.
///
/// If [value] is [String], the flag [caseSensitive] controls whether or not equality is case-sensitively compared.
///
/// Example:
///
///       final query = new Query<Employee>()
///         ..where.id = whereNotEqual(60000);
///
dynamic whereNotEqualTo(dynamic value, {bool caseSensitive: true}) {
  if (value is String) {
    return new StringExpression(
        value, PredicateStringOperator.equals,
        caseSensitive: caseSensitive,
        invertOperator: true);
  }
  return new ComparisonExpression(value, PredicateOperator.notEqual);
}


/// Query matcher that tests that a column is greater than [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is greater than (exclusive) [value] are returned. [value] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
/// this matcher selects rows where the assigned property is 'later than' [value]. For [String] properties,
/// rows are selected if the value is alphabetically 'after' [value].
///
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereGreaterThan(60000);
dynamic whereGreaterThan(dynamic value) {
  return new ComparisonExpression(value, PredicateOperator.greaterThan);
}

/// Query matcher that tests that a column is greater than or equal to [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is greater than or equal to [value] are returned. [value] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
/// this matcher selects rows where the assigned property is 'later than or the same time as' [value]. For [String] properties,
/// rows are selected if the value is alphabetically 'after or the same as' [value].
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereGreaterThanEqualTo(60000);
dynamic whereGreaterThanEqualTo(dynamic value) {
  return new ComparisonExpression(
      value, PredicateOperator.greaterThanEqualTo);
}

/// Query matcher that tests that a column is less than [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is less than (exclusive) [value] are returned. [value] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
/// this matcher selects rows where the assigned property is 'earlier than' [value]. For [String] properties,
/// rows are selected if the value is alphabetically 'before' [value].
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereLessThan(60000);
dynamic whereLessThan(dynamic value) {
  return new ComparisonExpression(value, PredicateOperator.lessThan);
}

/// Query matcher that tests that a column is less than [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is less than or equal to [value] are returned. [value] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
/// this matcher selects rows where the assigned property is 'earlier than or the same time as' [value]. For [String] properties,
/// rows are selected if the value is alphabetically 'before or the same as' [value].
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereLessThanEqualTo(60000);
dynamic whereLessThanEqualTo(dynamic value) {
  return new ComparisonExpression(
      value, PredicateOperator.lessThanEqualTo);
}

/// Query matcher that tests that a column contains [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// contains [value] are returned. [value] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [String] types. The substring [value] must be found in the stored string.
/// When matching [String] types, the flag [caseSensitive] controls whether strings are compared case-sensitively.
///
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.title = whereContains("Director");
///
dynamic whereContains(dynamic value, {bool caseSensitive: true}) {
  return new StringExpression(value, PredicateStringOperator.contains, caseSensitive: caseSensitive);
}
/// Query matcher that tests that a column begins with [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is a [String] that begins with [value] are returned.
///
/// This matcher can be used on [String] types. The flag [caseSensitive] controls whether strings are compared case-sensitively.
///
/// Example:Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereBeginsWith("B");
dynamic whereBeginsWith(String value, {bool caseSensitive: true}) {
  return new StringExpression(value, PredicateStringOperator.beginsWith, caseSensitive: caseSensitive);
}

/// Query matcher that tests that a column does not end with [value].
///
/// When assigned to a [Query.where] property, only rows where that [String]
/// does not end with [value] are returned.
///
/// This matcher can be used on [String] types. The flag [caseSensitive] controls whether strings are compared case-sensitively.
///
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereDoesNotEndWith("son");
dynamic whereDoesNotEndWith(String value, {bool caseSensitive: true}) {
  return new StringExpression(
      value, PredicateStringOperator.endsWith,
      caseSensitive: caseSensitive,
      invertOperator: true);
}

/// Query matcher that tests that a column does not contains [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// does not contains [value] are returned. [value] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [String] types. The substring [value] must be found in the stored string.
/// When matching [String] types, the flag [caseSensitive] controls whether strings are compared case-sensitively.
///
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.title = whereDoesNotContains("Director");
///
dynamic whereDoesNotContain(String value, {bool caseSensitive: true}) {
  return new StringExpression(
      value, PredicateStringOperator.contains,
      caseSensitive: caseSensitive,
      invertOperator: true);
}

/// Query matcher that tests that a column does not begins with [value].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is a [String] that does not begins with [value] are returned.
///
/// This matcher can be used on [String] types. The flag [caseSensitive] controls whether strings are compared case-sensitively.
///
/// Example:Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereDoesNotBeginsWith("B");
dynamic whereDoesNotBeginWith(String value, {bool caseSensitive: true}) {
  return new StringExpression(
      value, PredicateStringOperator.beginsWith,
      caseSensitive: caseSensitive,
      invertOperator: true);
}

/// Query matcher that tests that a column ends with [value].
///
/// When assigned to a [Query.where] property, only rows where that [String]
/// ends with [value] are returned.
///
/// This matcher can be used on [String] types. The flag [caseSensitive] controls whether strings are compared case-sensitively.
///
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.name = whereEndsWith("son");
dynamic whereEndsWith(String value, {bool caseSensitive: true}) {
  return new StringExpression(value, PredicateStringOperator.endsWith, caseSensitive: caseSensitive);
}

/// Query matcher that tests that a column's value is in [values].
///
/// When assigned to a [Query.where] property, only rows where where the property
/// value is one of [values] are returned.
///
/// This matcher can be used on [String], [int], [double], [bool] and [DateTime] types.
///
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.department = whereIn(["Engineering", "HR"]);
dynamic whereIn(Iterable<dynamic> values) {
  return new SetMembershipExpression(values.toList());
}

/// Query matcher that tests that a column is between [lhs] and [rhs].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is between [lhs] and [rhs] are returned. [lhs] and [rhs] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
/// this matcher selects rows where the assigned property is 'later than' [lhs] and 'earlier than' [rhs]. For [String] properties,
/// rows are selected if the value is alphabetically 'after' [lhs] and 'before' [rhs].
///
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereBetween(80000, 100000);
dynamic whereBetween(dynamic lhs, dynamic rhs) {
  return new RangeExpression(lhs, rhs, true);
}

/// Query matcher that tests that a column is not between [lhs] and [rhs].
///
/// When assigned to a [Query.where] property, only rows where that property
/// is not between [lhs] and [rhs] are returned. [lhs] and [rhs] must be the same type as the property
/// being assigned.
///
/// This matcher can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
/// this matcher selects rows where the assigned property is 'later than' [rhs] and 'earlier than' [lhs]. For [String] properties,
/// rows are selected if the value is alphabetically 'before' [lhs] and 'after' [rhs].
///
/// Example:
///
///       var query = new Query<Employee>()
///         ..where.salary = whereOutsideOf(80000, 100000);
dynamic whereOutsideOf(dynamic lhs, dynamic rhs) {
  return new RangeExpression(lhs, rhs, false);
}

/// Query matcher that tests that a relationship is related by [foreignKeyValue].
///
/// When assigned to a [Query.where] relationship property, only rows where that relationship
/// property's primary key is equal to [foreignKeyValue] will be returned. [foreignKeyValue]
/// must be the same type as the assigned property's primary key.
///
/// This matcher can be used on [ManagedObject] types that have [Relate] metadata; i.e., properties that are backed by a foreign key.
///
///       var q = new Query<Employee>()
///         ..where.manager = whereRelatedByValue(managerID);
dynamic whereRelatedByValue(dynamic foreignKeyValue) {
  return new ComparisonExpression(
      foreignKeyValue, PredicateOperator.equalTo);
}

/// Query matcher that inverts another query matcher.
///
/// Creates a matcher that inverts [matcher]. For whatever results would be filtered
/// by [matcher], the inverted expression both:
///
/// - includes the results that would have been excluded
/// - excludes the results that would have been included
///
/// This inversion will not change control flags like checking for case-insensitivity.
///
/// For example, the following find's all users not named 'Bob'.
///
///       var q = new Query<User>()
///         ..where.name = whereNot(whereEqualTo("Bob"));
///
/// Note: null values are not evaluated. In the previous example, if name
/// were 'null' for some user, it would *not* be returned by the query.
///
dynamic whereNot(dynamic matcher) {
  if (matcher is! PredicateExpression) {
    throw new ArgumentError("Invalid argument to 'whereNot'. Must be another matcher, e.g. 'whereEqualTo'.");
  }
  return (matcher as PredicateExpression).inverse;
}

/// Query matcher that tests whether a column value is null.
///
/// When assigned to a [Query.where] property, only rows where that
/// property is null will be returned.
///
/// This matcher can be applied to any property type.
///
/// Example:
///
///       var q = new Query<Employee>()
///         ..where.manager = whereNull;
const dynamic whereNull = const NullCheckExpression(true);

/// Query matcher that tests whether a column value is not null.
///
/// When assigned to a [Query.where] property, only rows where that
/// property is not null will be returned.
///
/// This matcher can be applied to any property type.
///
/// Example:
///
///       var q = new Query<Employee>()
///         ..where.manager = whereNotNull;
const dynamic whereNotNull = const NullCheckExpression(false);
