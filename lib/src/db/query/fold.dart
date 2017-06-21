import 'dart:async';
import '../managed/object.dart';
import 'query.dart';

/// Executes aggregate functions like average, count, sum, etc.
///
/// See instance methods for available aggregate functions.
///
/// See [Query.fold] for more details on usage.
abstract class QueryFoldOperation<T extends ManagedObject> {
  /// Computes the average of some [ManagedObject] property.
  ///
  /// [selector] identifies the property being averaged, e.g.
  ///
  ///         var query = new Query<User>();
  ///         var averageAge = await query.fold.average((user) => user.age);
  ///
  /// The property must be an attribute and its type must be an [num], i.e. [int] or [double].
  Future<double> average(num selector(T object));

  /// Counts the number of [ManagedObject] instances in the database.
  ///
  /// Note: this can be an expensive query. Consult the documentation
  /// for the underlying database.
  ///
  /// Example:
  ///
  ///         var query = new Query<User>();
  ///         var totalUsers = await query.fold.count();
  ///
  Future<int> count();

  /// Finds the maximum of some [ManagedObject] property.
  ///
  /// [selector] identifies the property being evaluated, e.g.
  ///
  ///         var query = new Query<User>();
  ///         var oldestUser = await query.fold.maximum((user) => user.age);
  ///
  /// The property must be an attribute and its type must be [String], [int], [double], or [DateTime].
  Future<U> maximum<U>(U selector(T object));

  /// Finds the minimum of some [ManagedObject] property.
  ///
  /// [selector] identifies the property being evaluated, e.g.
  ///
  ///         var query = new Query<User>();
  ///         var youngestUser = await query.fold.minimum((user) => user.age);
  ///
  /// The property must be an attribute and its type must be [String], [int], [double], or [DateTime].
  Future<U> minimum<U>(U selector(T object));


  /// Finds the sum of some [ManagedObject] property.
  ///
  /// [selector] identifies the property being evaluated, e.g.
  ///
  ///         var query = new Query<User>();
  ///         var yearsLivesByAllUsers = await query.fold.sum((user) => user.age);
  ///
  /// The property must be an attribute and its type must be an [num], i.e. [int] or [double].
  Future<U> sum<U extends num>(U selector(T object));
}