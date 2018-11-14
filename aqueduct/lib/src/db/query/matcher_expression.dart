import 'package:aqueduct/src/db/managed/key_path.dart';

import '../managed/managed.dart';
import 'matcher_internal.dart';
import 'query.dart';

/// Contains methods for adding logical expressions to properties when building a [Query].
///
/// You do not create instances of this type directly, but instead are returned an instance when selecting a property
/// of an object in [Query.where]. You invoke methods from this type to add an expression to the query for the selected property.
/// Example:
///
///         final query = new Query<Employee>()
///           ..where((e) => e.name).equalTo("Bob");
///
class QueryExpression<T, U, InstanceType> {
  QueryExpression(this.keyPath);

  QueryExpression.byAddingKey(QueryExpression<T, U, InstanceType> original,
      ManagedPropertyDescription byAdding)
      : keyPath = KeyPath.byAddingKey(original.keyPath, byAdding),
        _expression = original.expression;

  final KeyPath keyPath;

  // todo: This needs to be extended to an expr tree
  PredicateExpression get expression => _expression;

  set expression(PredicateExpression expr) {
    if (_invertNext) {
      _expression = expr.inverse;
      _invertNext = false;
    } else {
      _expression = expr;
    }
  }

  bool _invertNext = false;
  PredicateExpression _expression;

  /// Inverts the next expression.
  ///
  /// You use this method to apply an inversion to the expression that follows. For example,
  /// the following example would only return objects where the 'id' is  *not* equal to '5'.
  ///
  ///         final query = new Query<Employee>()
  ///           ..where((e) => e.name).not.equalTo("Bob");
  QueryExpression<T, U, InstanceType> get not {
    _invertNext = !_invertNext;

    return this;
  }

  /// Adds an equality expression to a query.
  ///
  /// A query will only return objects where the selected property is equal to [value].
  ///
  /// This method can be used on [int], [String], [bool], [double] and [DateTime] types.
  ///
  /// If [value] is [String], the flag [caseSensitive] controls whether or not equality is case-sensitively compared.
  ///
  /// Example:
  ///
  ///       final query = new Query<User>()
  ///         ..where((u) => u.id ).equalTo(1);
  ///
  equalTo(T value,
      {bool caseSensitive = true}) {
    if (value is String) {
      expression = StringExpression(value, PredicateStringOperator.equals,
          caseSensitive: caseSensitive);
    } else {
      expression = ComparisonExpression(value, PredicateOperator.equalTo);
    }
  }

  /// Adds an 'not equal' expression to a query.
  ///
  /// A query will only return objects where the selected property is *not* equal to [value].
  ///
  /// This method can be used on [int], [String], [bool], [double] and [DateTime] types.
  ///
  /// If [value] is [String], the flag [caseSensitive] controls whether or not equality is case-sensitively compared.
  ///
  /// Example:
  ///
  ///       final query = new Query<Employee>()
  ///         ..where((e) => e.id).notEqualTo(60000);
  ///
  notEqualTo(T value,
      {bool caseSensitive = true}) {
    if (value is String) {
      expression = StringExpression(value, PredicateStringOperator.equals,
          caseSensitive: caseSensitive, invertOperator: true);
    } else {
      expression = ComparisonExpression(value, PredicateOperator.notEqual);
    }
  }

  /// Adds a 'greater than' expression to a query.
  ///
  /// A query will only return objects where the selected property is greater than [value].
  ///
  /// This method can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
  /// this method selects rows where the assigned property is 'later than' [value]. For [String] properties,
  /// rows are selected if the value is alphabetically 'after' [value].
  ///
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((e) => e.salary).greaterThan(60000);
  greaterThan(T value) {
    expression = ComparisonExpression(value, PredicateOperator.greaterThan);
    }

  /// Adds a 'greater than or equal to' expression to a query.
  ///
  /// A query will only return objects where the selected property is greater than [value].
  ///
  /// This method can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
  /// this method selects rows where the assigned property is 'later than or the same time as' [value]. For [String] properties,
  /// rows are selected if the value is alphabetically 'after or the same as' [value].
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((e) => e.salary).greaterThanEqualTo(60000);
  greaterThanEqualTo(T value) {
    expression =
        ComparisonExpression(value, PredicateOperator.greaterThanEqualTo);
    }

  /// Adds a 'less than' expression to a query.
  ///
  /// A query will only return objects where the selected property is less than [value].
  ///
  /// This method can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
  /// this method selects rows where the assigned property is 'earlier than' [value]. For [String] properties,
  /// rows are selected if the value is alphabetically 'before' [value].
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((e) => e.salary).lessThan(60000);
  lessThan(T value) {
    expression = ComparisonExpression(value, PredicateOperator.lessThan);
    }

  /// Adds a 'less than or equal to' expression to a query.
  ///
  /// A query will only return objects where the selected property is less than or equal to [value].
  ///
  /// This method can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
  /// this method selects rows where the assigned property is 'earlier than or the same time as' [value]. For [String] properties,
  /// rows are selected if the value is alphabetically 'before or the same as' [value].
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((e) => e.salary).lessThanEqualTo(60000);
  lessThanEqualTo(T value) {
    expression = ComparisonExpression(value, PredicateOperator.lessThanEqualTo);
    }

  /// Adds a 'contains string' expression to a query.
  ///
  /// A query will only return objects where the selected property contains the string [value].
  ///
  /// This method can be used on [String] types. The substring [value] must be found in the stored string.
  /// The flag [caseSensitive] controls whether strings are compared case-sensitively.
  ///
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((s) => s.title).contains("Director");
  ///
   contains(String value,
      {bool caseSensitive = true}) {
    expression = StringExpression(value, PredicateStringOperator.contains,
        caseSensitive: caseSensitive);
    }

  /// Adds a 'begins with string' expression to a query.
  ///
  /// A query will only return objects where the selected property is begins with the string [value].
  ///
  /// This method can be used on [String] types. The flag [caseSensitive] controls whether strings are compared case-sensitively.
  ///
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((s) => s.name).beginsWith("B");
  beginsWith(String value,
      {bool caseSensitive = true}) {
    expression = StringExpression(value, PredicateStringOperator.beginsWith,
        caseSensitive: caseSensitive);
    }

  /// Adds a 'ends with string' expression to a query.
  ///
  /// A query will only return objects where the selected property is ends with the string [value].
  ///
  /// This method can be used on [String] types. The flag [caseSensitive] controls whether strings are compared case-sensitively.
  ///
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((e) => e.name).endsWith("son");
  endsWith(String value,
      {bool caseSensitive = true}) {
    expression = StringExpression(value, PredicateStringOperator.endsWith,
        caseSensitive: caseSensitive);

  }

  /// Adds a 'equal to one of' expression to a query.
  ///
  /// A query will only return objects where the selected property is equal to one of the [values].
  ///
  /// This method can be used on [String], [int], [double], [bool] and [DateTime] types.
  ///
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((e) => e.department).oneOf(["Engineering", "HR"]);
  oneOf(Iterable<T> values) {
    if (values?.isEmpty ?? true) {
      throw ArgumentError("'Query.where.oneOf' cannot be the empty set or null.");
    }
    expression = SetMembershipExpression(values.toList());
    }

  /// Adds a 'between two values' expression to a query.
  ///
  /// A query will only return objects where the selected property is between than [lhs] and [rhs].
  ///
  /// This method can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
  /// this method selects rows where the assigned property is 'later than' [lhs] and 'earlier than' [rhs]. For [String] properties,
  /// rows are selected if the value is alphabetically 'after' [lhs] and 'before' [rhs].
  ///
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((e) => e.salary).between(80000, 100000);
  between(T lhs, T rhs) {
    expression = RangeExpression(lhs, rhs, within: true);

  }

  /// Adds a 'outside of the range crated by two values' expression to a query.
  ///
  /// A query will only return objects where the selected property is not within the range established by [lhs] to [rhs].
  ///
  /// This method can be used on [int], [String], [double] and [DateTime] types. For [DateTime] properties,
  /// this method selects rows where the assigned property is 'later than' [rhs] and 'earlier than' [lhs]. For [String] properties,
  /// rows are selected if the value is alphabetically 'before' [lhs] and 'after' [rhs].
  ///
  /// Example:
  ///
  ///       var query = new Query<Employee>()
  ///         ..where((e) => e.salary).outsideOf(80000, 100000);
  outsideOf(T lhs, T rhs) {
    expression = RangeExpression(lhs, rhs, within: false);

  }

  /// Adds an equality expression for foreign key columns to a query.
  ///
  /// A query will only return objects where the selected object's primary key is equal to [identifier].
  ///
  /// This method may only be used on belongs-to relationships; i.e., those that have a [Relate] annotation.
  /// The type of [identifier] must match the primary key type of the selected object this expression is being applied to.
  ///
  ///       var q = new Query<Employee>()
  ///         ..where((e) => e.manager).identifiedBy(5);
  identifiedBy(dynamic identifier) {
    expression = ComparisonExpression(identifier, PredicateOperator.equalTo);

  }

  /// Adds a 'null check' expression to a query.
  ///
  /// A query will only return objects where the selected property is null.
  ///
  /// This method can be applied to any property type.
  ///
  /// Example:
  ///
  ///       var q = new Query<Employee>()
  ///         ..where((e) => e.manager).isNull();
  isNull() {
    expression = const NullCheckExpression(shouldBeNull: true);

  }

  /// Adds a 'not null check' expression to a query.
  ///
  /// A query will only return objects where the selected property is not null.
  ///
  /// This method can be applied to any property type.
  ///
  /// Example:
  ///
  ///       var q = new Query<Employee>()
  ///         ..where((e) => e.manager).isNotNull();
  isNotNull() {
    expression = const NullCheckExpression(shouldBeNull: false);
    }
}
